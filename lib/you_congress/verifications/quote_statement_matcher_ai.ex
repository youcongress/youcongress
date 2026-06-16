defmodule YouCongress.Verifications.QuoteStatementMatcherAI do
  @moduledoc """
  OpenAI-backed quote-to-statement matcher.

  It applies the same relevance standard as `VerifierAI`: a quote should match a
  statement only when it is about the complete statement or clearly implies the
  author's stance on the complete statement.
  """

  @behaviour YouCongress.Verifications.QuoteStatementMatcher

  alias YouCongress.Opinions.Opinion

  @model :"gpt-5.4"
  @timeout_in_min 120
  @answers ["for", "against", "abstain"]

  @impl true
  def match_statements(%Opinion{} = _opinion, []), do: {:ok, []}

  def match_statements(%Opinion{} = opinion, statements) when is_list(statements) do
    opinion = YouCongress.Repo.preload(opinion, :author)

    with {:ok, data} <- ask_gpt(prompt(opinion, statements)),
         {:ok, matches} <- process_response(data) do
      {:ok, matches}
    end
  end

  defp prompt(opinion, statements) do
    author = opinion.author && opinion.author.name

    statements_text =
      statements
      |> Enum.map_join("\n", fn statement -> "- #{statement.id}: #{statement.title}" end)

    """
    Select every statement from the list where the quote establishes the author's
    position on the complete statement.

    Author: #{author || "Unknown"}
    Date: #{Opinion.display_date(opinion) || "Unknown"}
    Source URL: #{opinion.source_url || "None provided"}
    Quote:
    \"\"\"
    #{opinion.content}
    \"\"\"

    Statements:
    #{statements_text}

    Use the same strict standard as relevance verification. A quote qualifies for
    a statement if it either:
    - is directly about the COMPLETE statement; or
    - is about something else, but clearly implies that the author supports,
      opposes, or abstains on the COMPLETE statement.

    The author's position on the COMPLETE statement must be clear from the quote.
    Do not accept a quote that only relates to one word, theme, subtopic, or a
    nearby issue unless it also implies the author's position on the COMPLETE
    statement. Do not infer a position from general sentiment, party membership,
    job title, or facts outside the quote.

    Return only matches that should receive "ai_verified" in a later strict
    relevance verification. Do not return matches that would be "disputed" or
    "ai_unverifiable"; if uncertain, leave the statement unmatched.

    For each match, choose:
    - "for": the quote clearly supports the statement.
    - "against": the quote clearly opposes the statement.
    - "abstain": the quote is explicitly neutral/undecided on the statement.
    If there are no strong matches, return an empty matches array.
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
        "input" => [
          %{
            "role" => "system",
            "content" =>
              "You judge whether a quote establishes an author's stance on policy statements as a whole. Accept direct relevance or clear implication; reject partial or adjacent topics unless they imply a stance on the complete statement."
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

  defp process_response(resp) do
    content = Map.get(resp, "output_text") || extract_output_text(resp)

    with content when is_binary(content) <- content,
         {:ok, %{"matches" => matches}} when is_list(matches) <- Jason.decode(content) do
      {:ok, matches}
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
            "Only high-confidence statements where the quote establishes the author's stance on the complete statement.",
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
                description: "Author's position on the complete statement"
              },
              "comment" => %{
                type: "string",
                description: "Short justification using the quote's wording"
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
