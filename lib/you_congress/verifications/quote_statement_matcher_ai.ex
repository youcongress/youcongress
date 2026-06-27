defmodule YouCongress.Verifications.QuoteStatementMatcherAI do
  @moduledoc """
  OpenAI-backed quote-to-statement matcher.

  It applies the same relevance standard as `VerifierAI`: a quote should match a
  statement when it is on-topic and provides a determinable stance signal on the
  COMPLETE statement. `submit/2` starts a background Responses API job and
  `check_job_status/1` polls for the parsed matches.
  """

  @behaviour YouCongress.Verifications.QuoteStatementMatcher

  alias YouCongress.Opinions.Opinion

  @model :"gpt-5.4"
  @timeout_in_min 120
  @answers ["for", "against", "abstain"]

  @impl true
  def submit(%Opinion{} = opinion, statements) when is_list(statements) do
    opinion = YouCongress.Repo.preload(opinion, :author)

    with {:ok, data} <- ask_gpt(prompt(opinion, statements)),
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
              process_completed_job(resp)

            {:ok, %{"status" => "failed", "error" => error}} ->
              {:error, "Job failed: #{inspect(error)}"}

            {:ok, %{"status" => _status}} ->
              {:ok, :in_progress}

            error ->
              {:error, "Failed to parse polling response: #{inspect(error)}"}
          end

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "Polling failed (#{status}): #{truncate_body(body)}"}

        {:error, reason} ->
          {:error, "Polling connection failed: #{inspect(reason)}"}
      end
    end
  end

  defp prompt(opinion, statements) do
    author = opinion.author && opinion.author.name

    statements_text =
      statements
      |> Enum.map_join("\n", fn statement -> "- #{statement.id}: #{statement.title}" end)

    """
    Select every statement from the list where the quote is on-topic and provides
    enough signal that the author's stance on the COMPLETE statement is
    determinable.

    Author: #{author || "Unknown"}
    Date: #{Opinion.display_date(opinion) || "Unknown"}
    Source URL: #{opinion.source_url || "None provided"}
    Quote:
    \"\"\"
    #{opinion.content}
    \"\"\"

    Statements:
    #{statements_text}

    Use the same standard as relevance and vote verification. A quote qualifies
    for a statement if it either:
    - is directly about the COMPLETE statement's claim, proposal, or question; or
    - strongly implies through its ordinary meaning that the author supports,
      opposes, or abstains on the COMPLETE statement.

    The quote need not restate every part of the COMPLETE statement or amount to
    strict logical proof. Match it when one position on the COMPLETE statement is
    substantially more likely than the alternatives based on the quote itself.
    For example, a prediction that AI will create a labor shortage strongly
    implies support for "AI will create more jobs than it destroys", and a quote
    about AI-driven worker replacement can strongly imply opposition to that same
    COMPLETE statement.

    Do not accept a quote that only relates to one word, theme, subtopic, or a
    nearby issue unless the quote supplies a necessary connection that strongly
    implies the author's position on the COMPLETE statement. Do not infer a
    position from general sentiment, party membership, job title, or facts
    outside the quote.

    Return only matches that should receive "ai_verified" in later relevance and
    vote verification. Leave a statement unmatched when no position is
    substantially more likely, not merely because reasonable inference is
    required.

    For each match, choose:
    - "for": the quote explicitly or strongly implies support for the statement.
    - "against": the quote explicitly or strongly implies opposition to the
      statement.
    - "abstain": the quote is explicitly neutral/undecided on the COMPLETE statement.
    If the position is implied rather than explicit, explain the inference and
    any limitation in the comment. If there are no strong matches, return an empty
    matches array.
    """
  end

  defp ask_gpt(prompt) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "Missing OPENAI_API_KEY"}
    else
      url = "https://api.openai.com/v1/responses"

      body = %{
        "model" => to_string(@model),
        "reasoning" => %{"effort" => "high"},
        "text" => %{
          "format" => %{
            "name" => "QuoteStatementMatches",
            "type" => "json_schema",
            "schema" => json_schema()
          }
        },
        "background" => true,
        "input" => [
          %{
            "role" => "system",
            "content" =>
              "You judge an author's most likely stance on COMPLETE statements from a quote. Accept explicit stances and strong ordinary-language implications. Reject merely adjacent topics, but do not require strict logical proof; explain inferential limitations in the comment."
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
          {:error, "OpenAI API error (#{status}): #{truncate_body(resp_body)}"}

        {:error, reason} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  defp extract_job_id(%{"id" => id}) when is_binary(id), do: {:ok, id}
  defp extract_job_id(_), do: {:error, "No Job ID found"}

  defp process_completed_job(resp) do
    content = Map.get(resp, "output_text") || extract_output_text(resp)

    with content when is_binary(content) <- content,
         {:ok, %{"matches" => matches}} when is_list(matches) <- Jason.decode(content) do
      {:ok, :completed, matches}
    else
      _ -> {:error, "Failed to parse quote-statement matches"}
    end
  end

  defp extract_output_text(%{"output" => output}) when is_list(output) do
    output
    |> Enum.find_value(fn
      %{"type" => "message", "content" => content} when is_list(content) ->
        Enum.find_value(content, fn
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

  defp json_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "matches" => %{
          type: "array",
          description:
            "Only high-confidence COMPLETE statements where the quote is on-topic and one stance is substantially more likely.",
          items: %{
            type: "object",
            additionalProperties: false,
            properties: %{
              "statement_id" => %{
                type: "integer",
                description: "ID of one statement from the provided list"
              },
              "answer" => %{
                type: "string",
                enum: @answers,
                description: "Author's position on the COMPLETE statement"
              },
              "comment" => %{
                type: "string",
                description:
                  "Short justification using the quote's wording, including any inference and its limitations"
              }
            },
            required: ["statement_id", "answer", "comment"]
          }
        }
      },
      required: ["matches"]
    }
  end

  defp truncate_body(body) when is_binary(body) and byte_size(body) > 500 do
    binary_part(body, 0, 500) <> "..."
  end

  defp truncate_body(body), do: body
end
