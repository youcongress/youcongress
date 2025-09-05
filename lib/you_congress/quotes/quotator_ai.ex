defmodule YouCongress.Quotes.QuotatorAI do
  @moduledoc """
  Find and return a single relevant public-figure quote about a question using OpenAI.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @model :"gpt-5"

  @doc """
  Generate a quote for a question.

  ## Examples

      iex> YouCongress.Quotes.QuotatorAI.generate_quote("Should we build a CERN for AI?")
      {:ok, %{quote: %{...}, cost: 0.0001}}
  """
  @spec generate_quote(binary, list(binary)) :: {:ok, map} | {:error, binary}
  def generate_quote(question_title, exclude_author_names \\ []) do
    prompt = get_prompt(question_title, exclude_author_names)

    with {:ok, data} <- ask_gpt(prompt, @model),
         content <- OpenAIModel.get_content(data),
         {:ok, quote} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, @model) do
      {:ok, %{quote: quote, cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec get_prompt(binary, list(binary)) :: binary
  defp get_prompt(question_title, exclude_author_names) do
    exclusion_text =
      if Enum.empty?(exclude_author_names) do
        ""
      else
        excluded_names = Enum.join(exclude_author_names, ", ")
        "\n    - DO NOT use quotes from these authors: #{excluded_names}"
      end

    """
    Question: #{question_title}

    Task: find one quote of a public figure about the question above. Make sure the quote is relevant to what the question is asking, not just to a part of it. Determine whether the author agrees or disagrees with the question based on their quote and set the agree_rate field accordingly.

    Constraints:
    - The quote must be verbatim and attributable.
    - Prefer the original or primary source.
    - The source_url must include the exact quote text.
    - If the quote is from a document/open letter/paper with multiple signers, return the first 15 authors in order and indicate whether there are more than 15 authors.
    - Fill all fields in the JSON. Use empty string when unavailable.
    - Carefully analyze the quote to determine the author's agreement level and set agree_rate appropriately.#{exclusion_text}

    Output: Return ONLY a valid JSON object matching the schema.
    """
  end

  @spec ask_gpt(binary, OpenAIModel.t()) :: {:ok, map} | {:error, binary}
  defp ask_gpt(prompt, model) do
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
            "name" => "QuoteResult",
            "type" => "json_schema",
            "schema" => json_schema()
          }
        },
        "input" => [
          %{
            "role" => "system",
            "content" =>
              "You are a meticulous research assistant who only returns validated facts with exact citations. You may browse the web using web_search to find primary sources that contain the exact quote text. Prefer official or original sources over aggregators."
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

      case Finch.request(req, Swoosh.Finch, receive_timeout: 600_000) do
        {:ok, %Finch.Response{status: status, body: resp_body}} when status in 200..299 ->
          with {:ok, resp} <- Jason.decode(resp_body) do
            IO.inspect(resp, label: "----------------- resp")
            content =
              Map.get(resp, "output_text") ||
                extract_output_text(resp)

            usage = Map.get(resp, "usage", %{})
            prompt_tokens = Map.get(usage, "input_tokens") || Map.get(usage, "prompt_tokens") || 0

            completion_tokens =
              Map.get(usage, "output_tokens") || Map.get(usage, "completion_tokens") || 0

            compat = %{
              "choices" => [
                %{"message" => %{"content" => content || ""}}
              ],
              "usage" => %{
                "prompt_tokens" => prompt_tokens,
                "completion_tokens" => completion_tokens
              }
            }

            {:ok, compat}
          else
            _ -> {:error, "Failed to parse OpenAI response"}
          end

        {:ok, %Finch.Response{status: status, body: resp_body}} ->
          {:error, "OpenAI API error (#{status}): #{truncate_body(resp_body)}"}

        {:error, reason} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
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

  defp json_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "quote" => %{
          type: "object",
          additionalProperties: false,
          properties: %{
            "quote" => %{type: "string", description: "The exact quote string (one-two paragraphs maximum, verbatim, ideally not too short)"},
            "source_url" => %{type: "string", description: "Primary source URL that includes the exact quote"},
            "source_text" => %{type: "string", description: "One or a few words that describe the source (e.g. 'BBC')"},
            "context" => %{type: "string", description: "Exact quote with surrounding text before and after (if available)"}
          },
          required: [
            "quote",
            "source_url",
            "source_text",
            "context"
          ]
        },
        "authors" => %{
          type: "array",
          description:
            "First 15 authors in original order if multi-signer; otherwise, single author",
          items: %{
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
          minItems: 1,
          maxItems: 15
        },
        "more_than_15_authors" => %{
          type: "boolean",
          description: "Whether there are more than 15 authors"
        },
        "agree_rate" => %{
          type: "string",
          description: "How much the author agrees with the question",
          enum: [
            "Strongly agree",
            "Agree",
            "Abstain",
            "Disagree",
            "Strongly disagree"
          ]
        }
      },
      required: [
        "quote",
        "agree_rate",
        "authors",
        "more_than_15_authors"
      ]
    }
  end
end
