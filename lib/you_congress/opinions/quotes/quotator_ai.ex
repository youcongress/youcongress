defmodule YouCongress.Opinions.Quotes.QuotatorAI do
  @moduledoc """
  Find and return 20 relevant public-figure quotes about a question using OpenAI.
  """

  require Logger

  alias YouCongress.DigitalTwins.OpenAIModel
  alias YouCongress.Opinions.Quotes.Quotator

  @model :"gpt-5"
  @timeout_in_min 60

  def number_of_quotes, do: Quotator.number_of_quotes()

  @doc """
  Generate 20 quotes for a question.

  ## Examples

      iex> YouCongress.Opinions.Quotes.QuotatorAI.find_quotes("Should we build a CERN for AI?")
      {:ok,
        %{
          cost: 0.18691525000000004,
          quotes: [
            %{
              "agree_rate" => "Agree",
              "author" => %{
                "bio" => "EU Commission President",
                "name" => "Ursula von der Leyen",
                "twitter_username" => "",
                "wikipedia_url" => "https://en.wikipedia.org/wiki/Ursula_von_der_Leyen"
              },
              "quote" => "We want to replicate the success story of CERN in Geneva. As you all know, CERN holds the largest particle accelerator in the world, and it allows the best and the brightest minds in the world to work together. And we want the same to happen in our AI Gigafactory.",
              "source_url" => "https://www.reuters.com/technology/artificial-intelligence/quotes-eu-chief-von-der-leyens-ai-speech-paris-summit-2025-02-11/",
              "year" => "2025"
            },
            %{
              "agree_rate" => "Agree",
              "author" => %{
                "bio" => "DeepMind cofounder, CEO",
                "name" => "Demis Hassabis",
                "twitter_username" => "",
                "wikipedia_url" => "https://en.wikipedia.org/wiki/Demis_Hassabis"
              },
              "quote" => "I’d love for there to be an International CERN, basically, for AI, where you get the top researchers in the world and you go: Look, let’s focus on the final few years of this project […] and really get it right.",
              "source_url" => "https://cfg.eu/cern-for-ai/",
              "year" => "2025"
            },
            ...
          ]
        }
  """
  @spec find_quotes(binary, list(binary)) ::
          {:ok, %{quotes: list, cost: number}} | {:error, binary}
  def find_quotes(question_title, exclude_author_names \\ []) do
    prompt = get_prompt(question_title, exclude_author_names)

    with {:ok, data} <- ask_gpt(prompt, @model),
         content <- OpenAIModel.get_content(data),
         {:ok, decoded} <- Jason.decode(content),
         quotes when is_list(quotes) <- Map.get(decoded, "quotes"),
         cost <- OpenAIModel.get_cost(data, @model) do
      {:ok, %{quotes: quotes, cost: cost}}
    else
      quotes when is_nil(quotes) -> {:error, "Missing quotes in response"}
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

    Task: find #{number_of_quotes()} quotes from different public figures where its clear that they agree or disagree the whole question above – not just a part of it (this is vital).

    Constraints:
    - Each of the #{number_of_quotes()} quotes must be verbatim and attributable.
    - Quotes must refer to the whole question and not just a part of it. For example, if the question is "Should a CERN for AI have a location with thousands of researchers?", quotes should make reference to a centralized or partially centralized CERN of AI with thousands of researchers in the same place – not just quotes about a CERN for AI or a CERN for AI as a network of AI researchers.
    - Quotes should be of two or three paragraphs long and at least three sentences long, if possible.
    - If the quote is in a different language, it should be translated to English.
    - Ideally, quotes should be informative about the reasons why they agree or provide other useful information related to the question.
    - Prefer the original or primary source or, in its absence, a reliable secondary source.
    - The source_url must include the exact quote text.
    - wikipedia_url and https://x.com/[twitter_username] must exist and belong to the author.
    - Authors must be experts, public figures or relevant organisations.
    - The author is the person who wrote the quote. Do not use the media outlet as the author unless the quote is from an editorial by that outlet.
    - Do not include quotes from a document/open letter/paper with multiple signers.
    - The quote must have one single author, a person or an organisation.
    - Fill all fields in the JSON. Use empty string when unavailable.
    - Carefully analyze each quote to determine the author's agreement level and set agree_rate appropriately.
    - Do not repeat any author across the #{number_of_quotes()} quotes. No name that appears in any item's authors.name may appear in any other item.#{exclusion_text}

    Output: Return ONLY a valid JSON object matching the schema with #{number_of_quotes()} items (if there are enough quotes that are relevant to the whole question).
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
            "name" => "QuotesResult",
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

      case Finch.request(req, Swoosh.Finch, receive_timeout: @timeout_in_min * 60 * 1000) do
        {:ok, %Finch.Response{status: status, body: resp_body}} when status in 200..299 ->
          case Jason.decode(resp_body) do
            {:ok, resp} ->
              Logger.warning("----------------- resp: #{inspect(resp)}")

              content =
                Map.get(resp, "output_text") ||
                  extract_output_text(resp)

              cached_input_tokens = resp["usage"]["input_tokens_details"]["cached_tokens"] || 0

              prompt_tokens = resp["usage"]["input_tokens"] - cached_input_tokens

              completion_tokens =
                resp["usage"]["output_tokens"] || 0

              compat = %{
                "choices" => [
                  %{"message" => %{"content" => content || ""}}
                ],
                "usage" => %{
                  "prompt_tokens" => prompt_tokens,
                  "completion_tokens" => completion_tokens,
                  "cached_input_tokens" => cached_input_tokens
                }
              }

              {:ok, compat}

            _ ->
              {:error, "Failed to parse OpenAI response"}
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
        "quotes" => %{
          type: "array",
          description:
            "#{number_of_quotes()} quotes (if the quotes are relevant to the whole question), each with author and metadata. Do not repeat any author across items.",
          minItems: number_of_quotes(),
          maxItems: number_of_quotes(),
          items: %{
            type: "object",
            additionalProperties: false,
            properties: %{
              "quote" => %{
                type: "string",
                description:
                  "The exact quote string (one-three paragraphs maximum, verbatim, ideally of at least three sentences long). Don't use quotation marks."
              },
              "source_url" => %{
                type: "string",
                description: "Primary source URL that includes the exact quote"
              },
              "year" => %{type: "string", description: "Year of the quote"},
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
                description: "How much the author agrees with the question",
                enum: [
                  "Strongly agree",
                  "Agree",
                  "Disagree",
                  "Strongly disagree"
                ]
              }
            },
            required: [
              "quote",
              "source_url",
              "year",
              "author",
              "agree_rate"
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
