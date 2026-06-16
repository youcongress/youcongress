defmodule YouCongress.Opinions.Quotes.FreshQuoteFinderAI do
  @moduledoc """
  OpenAI-backed discovery for fresh, source-validated AI-related quotes.
  """

  @behaviour YouCongress.Opinions.Quotes.FreshQuoteFinder

  require Logger

  alias YouCongress.DigitalTwins.OpenAIModel

  @model :"gpt-5.4"
  @timeout_in_min 120

  @impl true
  def find_quote(recent_quotes, opts \\ []) when is_list(recent_quotes) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    limit = Keyword.get(opts, :limit, 1)
    statements = Keyword.get(opts, :statements, [])
    prompt = get_prompt(recent_quotes, statements, now, limit)

    with {:ok, data} <- ask_gpt(prompt, @model),
         {:ok, job_id} <- extract_job_id(data) do
      {:ok, job_id}
    end
  end

  @impl true
  def check_job_status(job_id) when is_binary(job_id) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "Missing OPENAI_API_KEY"}
    else
      url = "https://api.openai.com/v1/responses/#{job_id}"

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer " <> api_key}
      ]

      req = Finch.build(:get, url, headers)

      case Finch.request(req, Swoosh.Finch, receive_timeout: 30_000) do
        {:ok, %Finch.Response{status: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"status" => "completed"} = resp} ->
              {:ok, :completed, process_completed_job(resp)}

            {:ok, %{"status" => "failed", "error" => error}} ->
              {:error, "Job failed: #{inspect(error)}"}

            {:ok, %{"status" => status}} ->
              Logger.debug("Fresh quote job #{job_id} is #{status}")
              {:ok, :in_progress}

            _ ->
              {:error, "Failed to parse polling response"}
          end

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "Polling failed (#{status}): #{truncate_body(body)}"}

        {:error, reason} ->
          {:error, "Polling connection failed: #{inspect(reason)}"}
      end
    end
  end

  defp get_prompt(recent_quotes, statements, now, limit) do
    window_start = DateTime.add(now, -24, :hour)

    """
    You are helping populate YouCongress (youcongress.org) with real, sourced quotes from notable public figures and experts.

    Objective:
    Find up to #{limit} fresh quote published in the last 24 hours about AI governance, AI safety, AI's impact on jobs, or AI's broader implications for society, and only if the quote fully matches at least one provided YouCongress statement.

    Current UTC time: #{DateTime.to_iso8601(now)}
    Freshness window starts at UTC: #{DateTime.to_iso8601(window_start)}

    Existing recent YouCongress quotes:
    #{Jason.encode!(recent_quotes)}

    Existing YouCongress statements:
    #{Jason.encode!(statements)}

    Research workflow:
    1. Search the web for a real quote published in the freshness window.
    2. Prefer primary sources: speeches, testimony, interviews, official blog posts, reports, transcripts, or accessible official social posts.
    3. Fetch the source page. Do not rely on search snippets.
    4. Check the existing recent YouCongress quotes and do not return duplicates or substantially identical quotes.
    5. Check the provided YouCongress statements and discard any quote that does not qualify for at least one complete statement.

    Complete-statement relevance standard:
    A quote qualifies for a statement if it either:
    - is directly about the COMPLETE statement; or
    - is about something else, but clearly implies that the author supports, opposes, or abstains on the COMPLETE statement.

    The author's position on the COMPLETE statement must be clear from the quote.
    Do not accept a quote that only relates to one word, theme, subtopic, or a nearby issue unless it also implies the author's position on the COMPLETE statement.
    Do not infer a position from general sentiment, party membership, job title, or facts outside the quote.

    Validation rules:
    - The source URL must contain the exact quote, allowing only faithful translation or [...] for omitted text.
    - The quote must be attributed to the returned author.
    - The publication date must be within the freshness window.
    - The quote must express a clear policy position, not just a factual observation.
    - The quote must be suitable as a standalone quote.
    - The quote topic must be AI governance, AI safety, AI's impact on jobs, or AI's societal implications.
    - The quote must clearly establish the author's position on at least one provided complete statement.
    - If a candidate fails any rule, discard it and keep searching.

    Quote quality rules:
    - Only use real, verifiable, verbatim quotes. Never fabricate, paraphrase, or invent attribution.
    - If all quote text is not consecutive, use [...] for omitted text. Do not use more than two [...] in a quote.
    - If the source quote is not in English, translate it to English and keep the meaning faithful.
    - Do not include quotes from documents, open letters, petitions, or papers with multiple signers unless the named author personally wrote the quoted passage.
    - The quote must have one clear author: a person or an organisation. Use the media outlet as author only for a signed/official editorial by that outlet.

    Metadata rules:
    - Fill every JSON field. Use an empty string when unavailable.
    - Use YYYY-MM-DD for date and "day" for date_precision.
    - If you provide wikipedia_url or twitter_username, the page/account must exist and belong to the author.
    - Authors must be experts, public figures, relevant organisations, or otherwise notable in the topic domain.

    Final QA before output:
    - Re-check that every source_url includes the quoted text.
    - Re-check that every quote is not already in the existing recent quotes inventory.
    - Re-check that every quote would receive "ai_verified" under the complete-statement relevance standard for at least one provided statement.
    - Remove any quote that fails verification, attribution, freshness, uniqueness, or complete-statement relevance.

    Output: Return ONLY a valid JSON object matching the schema with as many qualifying items as you can find, up to #{limit} item.
    """
  end

  @spec ask_gpt(binary(), OpenAIModel.t()) :: {:ok, map()} | {:error, binary()}
  defp ask_gpt(prompt, model) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "Missing OPENAI_API_KEY"}
    else
      url = "https://api.openai.com/v1/responses"

      body = %{
        "model" => to_string(model),
        "reasoning" => %{"effort" => "high"},
        "tools" => [
          %{"type" => "web_search"}
        ],
        "tool_choice" => "auto",
        "text" => %{
          "format" => %{
            "name" => "FreshQuotesResult",
            "type" => "json_schema",
            "schema" => json_schema()
          }
        },
        "background" => true,
        "input" => [
          %{
            "role" => "system",
            "content" =>
              "You are a meticulous research assistant who only returns validated facts with exact citations. Use web_search to find primary sources containing exact quote text. Reject quotes that do not establish a stance on at least one provided complete statement."
          },
          %{
            "role" => "user",
            "content" => "Return one JSON object strictly conforming to the provided JSON Schema."
          },
          %{"role" => "user", "content" => prompt}
        ]
      }

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer " <> api_key}
      ]

      req = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(req, Swoosh.Finch, receive_timeout: @timeout_in_min * 60 * 1000) do
        {:ok, %Finch.Response{status: status, body: resp_body}} when status in 200..299 ->
          case Jason.decode(resp_body) do
            {:ok, resp} -> {:ok, resp}
            _ -> {:error, "Failed to parse OpenAI response"}
          end

        {:ok, %Finch.Response{status: status, body: resp_body}} ->
          Logger.warning("Fresh quote OpenAI API error: #{inspect(resp_body)}")
          {:error, "OpenAI API error (#{status}): #{truncate_body(resp_body)}"}

        {:error, reason} ->
          Logger.warning("Fresh quote HTTP error: #{inspect(reason)}")
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  defp extract_job_id(%{"id" => id}) when is_binary(id), do: {:ok, id}
  defp extract_job_id(_), do: {:error, "No Job ID found"}

  defp process_completed_job(resp) do
    resp
    |> output_text()
    |> decode_quotes()
  end

  defp decode_quotes(nil), do: %{quotes: []}

  defp decode_quotes(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"quotes" => quotes}} when is_list(quotes) -> %{quotes: quotes}
      _ -> %{quotes: []}
    end
  end

  defp output_text(resp) do
    Map.get(resp, "output_text") || extract_output_text(resp)
  end

  defp extract_output_text(%{"output" => output}) when is_list(output) do
    output
    |> Enum.find_value(fn
      %{"type" => "message", "content" => content} when is_list(content) ->
        content
        |> Enum.find_value(fn
          %{"type" => "output_text", "text" => text} -> text
          %{"type" => "text", "text" => text} -> text
          _ -> nil
        end)

      %{"type" => "output_text", "text" => text} ->
        text

      %{"text" => text} when is_binary(text) ->
        text

      _ ->
        nil
    end)
  end

  defp extract_output_text(_), do: nil

  defp truncate_body(body) when is_binary(body) and byte_size(body) > 500 do
    binary_part(body, 0, 500) <> "..."
  end

  defp truncate_body(body), do: body

  defp json_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "quotes" => %{
          type: "array",
          minItems: 0,
          maxItems: 1,
          items: %{
            type: "object",
            additionalProperties: false,
            properties: %{
              "quote" => %{
                type: "string",
                description: "Exact quote text in English, verbatim or faithfully translated."
              },
              "source_url" => %{
                type: "string",
                description: "Source URL that contains the exact quote, attribution, and date."
              },
              "date" => %{
                type: "string",
                description: "Publication date in YYYY-MM-DD format."
              },
              "date_precision" => %{
                type: "string",
                enum: ["day"]
              },
              "author" => %{
                type: "object",
                additionalProperties: false,
                properties: %{
                  "name" => %{type: "string"},
                  "bio" => %{type: "string", description: "Author bio, max 7 words."},
                  "wikipedia_url" => %{type: "string"},
                  "twitter_username" => %{type: "string"}
                },
                required: ["name", "bio", "wikipedia_url", "twitter_username"]
              },
              "validation_note" => %{
                type: "string",
                description:
                  "Brief note explaining source/date/attribution validation and the strongest matching statement."
              }
            },
            required: [
              "quote",
              "source_url",
              "date",
              "date_precision",
              "author",
              "validation_note"
            ]
          }
        }
      },
      required: ["quotes"]
    }
  end
end
