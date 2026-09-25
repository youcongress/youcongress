defmodule YouCongress.Verifications.QuoteStatementMatcherAI do
  @moduledoc """
  OpenAI-backed quote-to-statement matcher.

  It applies the same relevance standard as `VerifierAI`: a quote should match a
  statement only when its own words cover every material key idea and provide a
  determinable stance signal on the COMPLETE statement. `submit/2` starts a
  background Responses API job and `check_job_status/1` polls for the matches.
  """

  @behaviour YouCongress.Verifications.QuoteStatementMatcher

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Verifications.KeyIdeaCoverage

  @model :"gpt-5.4-mini"
  @timeout_in_min 120
  @answers ["for", "against", "abstain"]

  @impl true
  def submit(%Opinion{} = opinion, statements) when is_list(statements) do
    opinion = YouCongress.Repo.preload(opinion, :author)

    with {:ok, data} <- ask_gpt(prompt(opinion, statements)) do
      extract_job_id(data)
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
    Select every statement from the list where the quote covers every material
    key idea and makes the author's stance on the COMPLETE statement determinable.

    Author: #{author || "Unknown"}
    Date: #{Opinion.display_date(opinion) || "Unknown"}
    Source URL: #{opinion.source_url || "None provided"}
    Quote:
    \"\"\"
    #{opinion.content}
    \"\"\"

    Statements:
    #{statements_text}

    Use the same standard as relevance and vote verification.
    #{KeyIdeaCoverage.prompt_instructions()}
    Do not infer a position from general sentiment, party membership, job title,
    or facts outside the quote.

    Return only matches that should receive "ai_verified" in later relevance and
    vote verification. Leave a statement unmatched when any material key idea is
    absent, even if the quote supports a broader, narrower, or adjacent claim.

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
              "Match a quote only when its own words cover every material key idea of the COMPLETE statement. Source context may clarify shorthand but cannot supply a missing idea. Reject broader, narrower, and adjacent claims."
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
            "Only COMPLETE statements whose every material key idea is covered by the quote and whose stance is determinable.",
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
              },
              "all_key_ideas_covered" => %{
                type: "boolean",
                description:
                  "True only when the quote covers every material idea in this statement."
              },
              "key_idea_coverage" => %{
                type: "array",
                minItems: 1,
                items: %{
                  type: "object",
                  additionalProperties: false,
                  properties: %{
                    "idea" => %{type: "string"},
                    "evidence" => %{
                      type: "string",
                      description: "Exact wording from the quote supporting this idea."
                    }
                  },
                  required: ["idea", "evidence"]
                }
              }
            },
            required: [
              "statement_id",
              "answer",
              "comment",
              "all_key_ideas_covered",
              "key_idea_coverage"
            ]
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
