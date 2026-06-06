defmodule YouCongress.Opinions.Quotes.QuotatorAI do
  @moduledoc """
  Find and return relevant public-figure quotes about a statement using OpenAI.
  """

  require Logger

  alias YouCongress.DigitalTwins.OpenAIModel
  alias YouCongress.Opinions.Quotes.Quotator

  @model :"gpt-5.4"
  @timeout_in_min 120

  def number_of_quotes, do: Quotator.number_of_quotes()

  @doc """
  Generate sourced quotes for a statement.

  ## Examples

      iex> YouCongress.Opinions.Quotes.QuotatorAI.find_quotes("Should we build a CERN for AI?")
      {:ok,
        %{
          cost: 0.18691525000000004,
          quotes: [
            %{
              "agree_rate" => "For",
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
              "agree_rate" => "For",
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

  alias YouCongress.Workers.QuotatorPollingWorker

  @spec find_quotes(
          integer,
          binary,
          list(binary),
          integer() | nil,
          integer(),
          integer(),
          integer()
        ) ::
          {:ok, :job_started} | {:error, binary}
  def find_quotes(
        statement_id,
        question_title,
        exclude_author_names,
        user_id,
        max_remaining_llm_calls,
        max_remaining_quotes,
        total_quotes_added \\ 0
      ) do
    prompt = get_prompt(question_title, exclude_author_names)

    with {:ok, data} <- ask_gpt(prompt, @model),
         {:ok, job_id} <- extract_job_id(data) do
      # Enqueue polling worker
      %{
        job_id: job_id,
        statement_id: statement_id,
        user_id: user_id,
        max_remaining_llm_calls: max_remaining_llm_calls,
        max_remaining_quotes: max_remaining_quotes,
        total_quotes_added: total_quotes_added
      }
      |> QuotatorPollingWorker.new()
      |> Oban.insert()

      {:ok, :job_started}
    else
      {:error, error} -> {:error, error}
    end
  end

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

  def check_polling_job_status(statement_id) do
    import Ecto.Query
    alias Oban.Job

    query =
      from(j in Job,
        where: j.worker == "YouCongress.Workers.QuotatorPollingWorker",
        where: fragment("?->>'statement_id' = ?", j.args, ^to_string(statement_id)),
        where: j.state in ["scheduled", "available", "executing", "retryable"]
      )

    YouCongress.Repo.exists?(query)
  end

  defp extract_job_id(%{"id" => id}), do: {:ok, id}
  defp extract_job_id(_), do: {:error, "No Job ID found"}

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
    You are helping populate YouCongress (youcongress.org) with real, sourced quotes from public figures on policy statements.

    Statement: #{question_title}

    Objective:
    Find up to #{number_of_quotes()} real quotes from different notable authors whose position on the statement can be classified as "For", "Against", or "Abstain".

    Research workflow:
    1. Search for quotes, interviews, speeches, testimony, articles, posts, reports, or transcripts about the exact statement topic.
    2. Prefer primary sources: official pages, transcripts, testimony, speeches, interviews, author-written articles, company/organisation posts, or direct social posts. Use reliable secondary sources only when they reproduce the exact quote and attribution.
    3. Prefer expert, academic, business, activist, civil-society, or other domain-relevant authors. Politicians are acceptable when they are notable and directly address the statement.
    4. Prefer recent quotes, especially 2026-or-later quotes for current AI governance, AI safety, or AI-in-society statements. Do not use a weak or partial quote merely because it is recent.
    5. Before returning a quote, verify that source_url exists, is accessible, attributes the quote to the author, and contains the exact quote text.
    6. Check existing exclusions and do not reuse authors that are already excluded.#{exclusion_text}

    Relevance rules (all are critical):
    - Each quote must address the COMPLETE statement, not just one word, theme, subtopic, or nearby issue. For example, for "Should we implement universal basic income?", use quotes about universal basic income as a complete policy, not quotes only about poverty reduction, stimulus, automation, or welfare reform.
    - The source quote must make the author's For/Against/Abstain position on the whole statement clear. Do not infer a position from general sentiment, party membership, job title, or unrelated comments.
    - If a quote supports only part of the statement, opposes only part of it, or would require extra assumptions to classify, omit it.
    - Favor quotes that include the author's reasoning, tradeoffs, evidence, or policy argument.

    Quote quality rules:
    - Only use real, verifiable, verbatim quotes. Never fabricate, paraphrase, or invent attribution.
    - If not enough qualifying quotes exist, return fewer quotes rather than padding the response with weak, unverifiable, duplicate, or fabricated items.
    - If all quote text is not consecutive, use [...] for omitted text. Do not use more than two [...] in a quote.
    - Quotes should be two or three paragraphs and at least three sentences when the source supports that length, but shorter quotes are acceptable when they clearly answer the statement.
    - If the source quote is not in English, translate it to English and keep the meaning faithful.
    - Do not include quotes from documents, open letters, petitions, or papers with multiple signers unless the named author personally wrote the quoted passage.
    - The quote must have one clear author: a person or an organisation. Use the media outlet as author only for a signed/official editorial by that outlet.

    Metadata rules:
    - Fill every JSON field. Use an empty string when unavailable.
    - If you provide wikipedia_url or twitter_username, the page/account must exist and belong to the author.
    - Authors must be experts, public figures, relevant organisations, or otherwise notable in the statement's domain.
    - Do not repeat any author across returned quotes. No name that appears in any item's author.name may appear in any other item.
    - Carefully set agree_rate to exactly one of "For", "Against", or "Abstain".
    - If the statement starts with `🇪🇸 Congreso, [date]`, it is about a vote in the Spanish Congreso de los Diputados. In that case, prioritize quotes about that vote from Spanish politicians and experts, without excluding relevant non-Spanish experts.

    Final QA before output:
    - Re-check that every source_url includes the quoted text.
    - Re-check that every quote is about the whole statement.
    - Remove any quote that fails verification, attribution, uniqueness, or relevance.

    Output: Return ONLY a valid JSON object matching the schema with as many qualifying items as you can find, up to #{number_of_quotes()} items.
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
        "background" => true,
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

    %{
      quotes: Map.get(decoded, "quotes"),
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

  defp json_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "quotes" => %{
          type: "array",
          description:
            "Up to #{number_of_quotes()} quotes, each relevant to the whole statement and with author metadata. Return fewer items rather than weak, duplicate, unverifiable, or fabricated quotes. Do not repeat any author across items.",
          minItems: 0,
          maxItems: number_of_quotes(),
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
                description: "The author's position on the whole statement",
                enum: [
                  "For",
                  "Against",
                  "Abstain"
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
