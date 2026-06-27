defmodule YouCongress.Opinions.Quotes.QuotatorAI do
  @moduledoc """
  Find and return relevant public-figure quotes about a statement using OpenAI.

  This module is not often used but external AI agents use our MCP tools to find and add quotes.
  """

  require Logger

  alias YouCongress.DigitalTwins.OpenAIModel
  alias YouCongress.Opinions.Quotes.Quotator

  @behaviour Quotator

  @model :"gpt-5.4"
  @timeout_in_min 120

  def number_of_quotes, do: Quotator.number_of_quotes()

  @doc """
  Start a background OpenAI job that finds sourced quotes for a statement.
  """

  alias YouCongress.Workers.QuotatorPollingWorker

  @impl true
  @spec find_quotes(
          integer,
          binary,
          list(binary),
          integer() | nil,
          integer(),
          integer(),
          integer()
        ) ::
          {:ok, :job_started} | {:error, term()}
  def find_quotes(
        statement_id,
        question_title,
        exclude_author_names,
        user_id,
        max_remaining_llm_calls,
        max_remaining_quotes,
        total_quotes_added \\ 0
      ) do
    limit = min(number_of_quotes(), max(max_remaining_quotes, 0))
    prompt = get_prompt(question_title, exclude_author_names, Date.utc_today(), limit)

    with :ok <- ensure_capacity(limit),
         {:ok, data} <- ask_gpt(prompt, @model, limit),
         {:ok, job_id} <- extract_job_id(data),
         {:ok, _job} <-
           enqueue_polling_job(%{
             job_id: job_id,
             statement_id: statement_id,
             user_id: user_id,
             max_remaining_llm_calls: max_remaining_llm_calls,
             max_remaining_quotes: max_remaining_quotes,
             total_quotes_added: total_quotes_added
           }) do
      {:ok, :job_started}
    else
      {:error, error} -> {:error, error}
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
              Logger.debug("Job #{job_id} completed")
              {:ok, :completed, process_completed_job(resp)}

            {:ok, %{"status" => "failed", "error" => error}} ->
              Logger.debug("Job #{job_id} failed: #{inspect(error)}")
              {:error, "Job failed: #{inspect(error)}"}

            {:ok, %{"status" => status}} ->
              Logger.debug("Job #{job_id} is #{status}")
              {:ok, :in_progress}

            error ->
              Logger.debug("Failed to parse polling response: #{inspect(error)}")
              {:error, "Failed to parse polling response"}
          end

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "Polling failed (#{status}): #{truncate_body(body)}"}

        {:error, reason} ->
          {:error, "Polling connection failed: #{inspect(reason)}"}
      end
    end
  end

  defp enqueue_polling_job(args) do
    args
    |> QuotatorPollingWorker.new()
    |> Oban.insert()
  end

  defp extract_job_id(%{"id" => id}) when is_binary(id), do: {:ok, id}
  defp extract_job_id(_), do: {:error, "No Job ID found"}

  defp ensure_capacity(limit) when limit > 0, do: :ok
  defp ensure_capacity(_limit), do: {:error, "No remaining quote capacity"}

  @spec get_prompt(binary(), list(binary()), Date.t(), pos_integer()) :: binary()
  defp get_prompt(statement_title, exclude_author_names, current_date, limit) do
    exclusion_text =
      if Enum.empty?(exclude_author_names) do
        ""
      else
        "\n    Authors already represented on this statement (do not return them):\n" <>
          Jason.encode!(exclude_author_names)
      end

    """
    You are helping populate YouCongress (youcongress.org) with real, sourced quotes from notable public figures, experts, and organisations.

    Statement: #{statement_title}
    Current UTC date: #{Date.to_iso8601(current_date)}

    Objective:
    Find up to #{limit} real quotes from different notable authors. Every returned quote must pass all three YouCongress AI checks: quote authenticity, relevance to the COMPLETE statement, and vote classification.

    Research workflow:
    1. Search the web for quotes, interviews, speeches, testimony, articles, posts, reports, or transcripts about the exact statement topic.
    2. Prefer primary sources: official pages, transcripts, testimony, speeches, interviews, author-written articles, company/organisation posts, or direct social posts. Use reliable secondary sources only when they reproduce the exact quote and attribution.
    3. Prefer expert, academic, business, activist, civil-society, or other domain-relevant authors. Politicians are acceptable when they are notable and directly address the statement.
    4. Fetch and inspect the source page. Never rely on a search-result snippet.
    5. Only return quotes published on or after January 1, #{current_date.year}. Prefer the newest strong evidence, but never trade verification quality for recency.
    6. Discard a candidate unless its quote, source, author, date, relevance, and stance all survive the checks below.#{exclusion_text}

    Quote authenticity check (must receive "ai_verified"):
    - The source URL itself must be accessible and contain the exact quote text, allowing only faithful English translation and [...] for omitted text.
    - The source must attribute the words to exactly the returned author and support the returned publication date.
    - Return the canonical quote text, source URL, date, date precision, and author metadata. If VerifierAI would need to correct any of those fields, discard or fix the candidate before returning it.
    - Only use real, verifiable, verbatim quotes. Never fabricate, paraphrase, or invent attribution.
    - If all quote text is not consecutive, use [...] for omitted text. Do not use more than two [...] in a quote.
    - Quotes should be two or three paragraphs and at least three sentences when the source supports that length, but shorter quotes are acceptable when they provide a determinable stance signal.
    - If the source quote is not in English, translate it to English and keep the meaning faithful.
    - Documents, open letters, petitions, declarations, manifestos, reports, and similar collective texts are acceptable when the source presents the quote as the wording of one named document or issuing coalition. In that case, use the document title or coalition as the author.
    - The quote must have exactly one clear author: one person, one organisation speaking on its own behalf, or one named document/issuing coalition. Never combine multiple people into one author. Use a media outlet as author only for its signed or official editorial.

    COMPLETE statement relevance check (must receive "ai_verified"):
    A quote qualifies if it either:
    - is directly about the COMPLETE statement's claim, proposal, or question; or
    - is about a narrower, causal, comparative, or underlying issue whose ordinary meaning makes one stance on the COMPLETE statement substantially more likely.

    Do not require the quote to restate every part of the COMPLETE statement or amount to strict logical proof. For example, a prediction that AI will create a labor shortage strongly implies support for "AI will create more jobs than it destroys", and a quote about AI-driven worker replacement can strongly imply opposition to that same COMPLETE statement.
    Do not accept a quote that only relates to one word, theme, subtopic, or nearby issue unless it also makes one stance on the COMPLETE statement substantially more likely.
    Do not infer a position from general sentiment, party membership, job title, or facts outside the quote.

    Vote check (must receive "ai_verified"):
    - Classify the stance based on what the quote says about the COMPLETE statement.
    - Use "For" when the quote explicitly or strongly implies support for the statement.
    - Use "Against" when the quote explicitly or strongly implies opposition to the statement.
    - Use "Abstain" only when the quote is explicitly neutral or undecided on the COMPLETE statement.
    - Do not require strict logical proof. If one position is substantially more likely than the alternatives, classify it and explain the inference in validation_note.
    - If the quote's stance would be "none" or is genuinely ambiguous, discard it. Never turn an unclear stance into "Abstain".

    Metadata rules:
    - Fill every JSON field. Use an empty string when unavailable.
    - Set date to the quote/source date. Use YYYY-MM-DD when the exact day is recoverable, YYYY-MM when only the month is known, or YYYY when only the year is known. Set date_precision to "day", "month", or "year" to match.
    - If you provide wikipedia_url or twitter_username, the page/account must exist and belong to the author.
    - Authors must be experts, public figures, relevant organisations, or otherwise notable in the statement's domain.
    - Do not repeat any author across returned quotes. No name that appears in any item's author.name may appear in any other item.
    - If the statement starts with `🇪🇸 Congreso, [date]`, it is about a vote in the Spanish Congreso de los Diputados. In that case, prioritize quotes about that vote from Spanish politicians and experts, without excluding relevant non-Spanish experts.

    Final QA before output:
    - Re-open every source URL and re-check exact text, attribution, and date.
    - Re-check that VerifierAI would mark the quote authentic without a correction.
    - Re-check that VerifierAI would mark its relevance to the COMPLETE statement "ai_verified".
    - Re-check that VerifierAI would derive the same For/Against/Abstain vote from the quote and cited source context if needed.
    - Remove any candidate that fails authenticity, attribution, freshness, uniqueness, COMPLETE statement relevance, or unambiguous vote classification.
    - If not enough candidates pass, return fewer quotes. An empty result is better than a weak or unverifiable quote.

    Output: Return ONLY a valid JSON object matching the schema with as many qualifying items as you can find, up to #{limit} items.
    """
  end

  @spec ask_gpt(binary(), OpenAIModel.t(), pos_integer()) ::
          {:ok, map()} | {:error, binary()}
  defp ask_gpt(prompt, model, limit) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "Missing OPENAI_API_KEY"}
    else
      url = "https://api.openai.com/v1/responses"

      body = %{
        "model" => to_string(model),
        "reasoning" => %{"effort" => "high"},
        # Enable browsing so the model can find and cite primary sources
        "tools" => [
          %{"type" => "web_search"}
        ],
        "tool_choice" => "auto",
        "text" => %{
          "format" => %{
            "name" => "QuotesResult",
            "type" => "json_schema",
            "schema" => json_schema(limit)
          }
        },
        "background" => true,
        "input" => [
          %{
            "role" => "system",
            "content" =>
              "You are a meticulous quote researcher. Use web_search to inspect primary sources, and reject any candidate that would fail quote-authenticity, COMPLETE statement relevance, or vote-answer verification."
          },
          %{
            "role" => "user",
            "content" => """
            Return one JSON object strictly conforming to the provided JSON Schema.
            """
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
          Logger.warning("ERROR ----------------- resp_body: #{inspect(resp_body)}")
          {:error, "OpenAI API error (#{status}): #{truncate_body(resp_body)}"}

        {:error, reason} ->
          Logger.warning("ERROR ----------------- reason: #{inspect(reason)}")
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  defp process_completed_job(resp) do
    content =
      Map.get(resp, "output_text") ||
        extract_output_text(resp)

    cached_input_tokens = get_in(resp, ["usage", "input_tokens_details", "cached_tokens"]) || 0
    _prompt_tokens = (get_in(resp, ["usage", "input_tokens"]) || 0) - cached_input_tokens
    _completion_tokens = get_in(resp, ["usage", "output_tokens"]) || 0

    decoded =
      case Jason.decode(content) do
        {:ok, decoded} -> decoded
        _ -> %{"quotes" => []}
      end

    quotes =
      case Map.get(decoded, "quotes") do
        quotes when is_list(quotes) -> quotes
        _ -> []
      end

    %{
      quotes: quotes,
      # TODO: Calculate cost if needed
      cost: 0.0
    }
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
    binary_part(body, 0, 500) <> "…"
  end

  defp truncate_body(body), do: body

  defp json_schema(limit) do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "quotes" => %{
          type: "array",
          description:
            "Up to #{limit} quotes that pass authenticity, COMPLETE statement relevance, and vote-answer verification. Return fewer items rather than weak, duplicate, unverifiable, or fabricated quotes. Do not repeat authors.",
          minItems: 0,
          maxItems: limit,
          items: %{
            type: "object",
            additionalProperties: false,
            properties: %{
              "quote" => %{
                type: "string",
                description:
                  "The exact quote string in English (one-three paragraphs maximum, verbatim or faithfully translated, ideally at least three sentences long). Do not use quotation marks."
              },
              "source_url" => %{
                type: "string",
                description:
                  "Primary source URL, or reliable secondary source URL when necessary, that includes the exact quote"
              },
              "date" => %{
                type: "string",
                description:
                  "Date of the quote. Use YYYY-MM-DD when the exact day is known, YYYY-MM when only month is known, or YYYY when only year is known."
              },
              "date_precision" => %{
                type: "string",
                description: "Precision of the date field",
                enum: [
                  "day",
                  "month",
                  "year"
                ]
              },
              "author" => %{
                type: "object",
                additionalProperties: false,
                properties: %{
                  "name" => %{type: "string", description: "Author name"},
                  "bio" => %{type: "string", description: "Author bio (max 7 words)"},
                  "wikipedia_url" => %{type: "string", description: "Author Wikipedia page URL"},
                  "twitter_username" => %{
                    type: "string",
                    description: "Author Twitter handle without @"
                  }
                },
                required: ["name", "bio", "wikipedia_url", "twitter_username"]
              },
              "agree_rate" => %{
                type: "string",
                description:
                  "The unambiguous position supported by the quote and cited source context if needed. Abstain means explicitly neutral or undecided, never unclear.",
                enum: [
                  "For",
                  "Against",
                  "Abstain"
                ]
              },
              "validation_note" => %{
                type: "string",
                description:
                  "Brief evidence that the source contains the exact quote, attribution and date, plus why the quote supports this vote on the COMPLETE statement."
              }
            },
            required: [
              "quote",
              "source_url",
              "date",
              "date_precision",
              "author",
              "agree_rate",
              "validation_note"
            ]
          }
        }
      },
      required: [
        "quotes"
      ]
    }
  end
end
