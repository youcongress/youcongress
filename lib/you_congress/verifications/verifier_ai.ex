defmodule YouCongress.Verifications.VerifierAI do
  @moduledoc """
  OpenAI-backed implementation of `YouCongress.Verifications.Verifier`.

  Uses the OpenAI Responses API in `background` mode with `web_search` so the
  model can check primary sources, exactly like
  `YouCongress.Opinions.Quotes.QuotatorAI`. `submit/2` starts a background job and
  returns its id; `check_job_status/1` polls it and returns the parsed result.

  Result maps (string keys):
  - `:quote` -> `%{"status" => ..., "comment" => ..., "correction" => ..., "model" => ...}`
  - `:relevance` -> `%{"status" => ..., "comment" => ..., "model" => ...}`
  - `:vote` -> `%{"correct_answer" => ..., "comment" => ..., "model" => ...}`
  """

  @behaviour YouCongress.Verifications.Verifier

  require Logger

  alias YouCongress.Repo
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes.Vote

  @model :"gpt-5.4"
  @timeout_in_min 120

  @statuses ["ai_verified", "ai_unverifiable", "disputed", "unverifiable", "unverified"]
  @answers ["for", "against", "abstain", "none"]

  @impl true
  def submit(subject_type, subject) do
    submit(subject_type, subject, [])
  end

  @impl true
  def submit(subject_type, subject, opts) do
    with {:ok, %{prompt: prompt, schema: schema, name: name, system: system} = spec} <-
           build(subject_type, subject, opts),
         {:ok, data} <- ask_gpt(prompt, schema, name, system, spec[:web_search] || false),
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

  # --- Per-subject prompt + schema -------------------------------------------

  defp build(subject_type, subject, opts)

  defp build(:quote, %Opinion{} = opinion, opts) do
    opinion = Repo.preload(opinion, :author)
    author = opinion.author && opinion.author.name
    allow_correction? = Keyword.get(opts, :allow_quote_correction?, true)

    prompt = """
    Verify whether the following quote is authentic.

    Author: #{author || "Unknown"}
    Date: #{Opinion.display_date(opinion) || "Unknown"}
    Source URL: #{opinion.source_url || "None provided"}
    Quote:
    \"\"\"
    #{opinion.content}
    \"\"\"

    Using web_search, confirm the quote is real and verbatim (allowing [...] for
    omitted text and faithful translation), that it is correctly attributed to the
    author, and that the source URL contains it.

    #{quote_correction_instructions(allow_correction?)}

    Choose a status:
    - "ai_verified": you confirmed the quote is real and correctly attributed.
    - "disputed": you found the quote is fabricated, materially altered, or misattributed.
    - "ai_unverifiable": you could not find enough evidence either way.
    - "unverifiable": the quote cannot be checked in principle.
    Always include a short comment citing what you found.
    """

    {:ok,
     %{
       prompt: prompt,
       schema: quote_status_schema(allow_correction?),
       name: "QuoteVerification",
       web_search: true,
       system:
         "You are a meticulous fact-checker. You only confirm a quote when a reliable source contains the exact text and attributes it to the author."
     }}
  end

  defp build(:relevance, %OpinionStatement{} = opinion_statement, _opts) do
    opinion_statement = Repo.preload(opinion_statement, [:opinion, :statement])
    opinion = opinion_statement.opinion
    statement = opinion_statement.statement

    prompt = """
    Verify whether the following quote establishes the author's position on the
    complete statement.

    Statement: #{statement.title}
    Quote:
    \"\"\"
    #{opinion.content}
    \"\"\"

    A quote qualifies if it either:
    - is directly about the COMPLETE statement; or
    - is about something else, but clearly implies that the author supports,
      opposes, or abstains on the COMPLETE statement.

    The author's position on the COMPLETE statement must be clear from the quote.
    Do not accept a quote that only relates to one word, theme, subtopic, or a
    nearby issue unless it also implies the author's position on the COMPLETE
    statement. Do not infer a position from general sentiment, party membership,
    job title, or facts outside the quote.

    Choose a status:
    - "ai_verified": the quote is directly about the whole statement, or clearly
      implies the author's support, opposition, or abstention on the whole
      statement.
    - "disputed": the quote does not make the author's position on the whole
      statement clear.
    - "ai_unverifiable": you cannot tell.
    Always include a short comment explaining your decision.
    """

    {:ok,
     %{
       prompt: prompt,
       schema: status_schema(),
       name: "RelevanceVerification",
       system:
         "You judge whether a quote establishes an author's stance on a policy statement as a whole. Accept direct relevance or clear implication; reject partial or adjacent topics unless they imply a stance on the complete statement."
     }}
  end

  defp build(:vote, %Vote{} = vote, _opts) do
    vote = Repo.preload(vote, [:opinion, :statement])
    opinion = vote.opinion
    statement = vote.statement

    prompt = """
    Determine the author's position on the statement based solely on the quote.

    Statement: #{statement.title}
    Quote:
    \"\"\"
    #{opinion && opinion.content}
    \"\"\"

    Current recorded answer: #{vote.answer}

    Based only on what the quote actually says, what is the author's most likely
    position on the whole statement? A position may be explicit or strongly
    implied by the quote's ordinary meaning. Do not require the quote to restate
    every part of the statement or amount to strict logical proof. When one
    position is substantially more likely than the alternatives, classify it as
    that position and explain the inference in the comment.

    For example, a prediction that AI will create a labor shortage strongly
    implies support for the statement "AI will create more jobs than it
    destroys", even though it does not explicitly compare jobs created and
    destroyed.

    Answer with exactly one of:
    - "for": the quote explicitly or strongly implies support for the statement.
    - "against": the quote explicitly or strongly implies opposition to the
      statement.
    - "abstain": the quote is explicitly neutral/undecided on the statement.
    - "none": no position is substantially more likely because the quote is
      genuinely ambiguous, merely adjacent to the issue, or missing a necessary
      connection to the statement. Do not choose "none" merely because some
      reasonable inference is required.
    Always include a short comment justifying the answer with the quote's wording.
    If the position is implied rather than explicit, identify that inference and
    any limitation in the evidence.
    """

    {:ok,
     %{
       prompt: prompt,
       schema: answer_schema(),
       name: "VoteVerification",
       system:
         "You classify an author's most likely stance on a statement from a quote. Accept explicit positions and strong ordinary-language implications. Choose \"none\" only when no stance is substantially more likely, and explain inferential limitations in the comment."
     }}
  end

  defp build(_subject_type, _subject, _opts), do: {:error, :invalid_subject}

  defp quote_correction_instructions(true) do
    """
    Also check whether the stored content, date, source URL, and author are the
    right canonical values. If the quote is authentic but any stored field is
    wrong and you can recover the right values from reliable evidence, return
    status "disputed" and include a correction object with the proper content,
    source_url, date, date_precision, and author metadata. Use null correction
    when no correction should be applied.

    For author corrections, return exactly one author name only when the quote has
    one individual author, or when an organisation is speaking on its own behalf.
    If a source lists multiple individual authors/signers and they are not
    speaking on behalf of an organisation, do not return a correction. Return
    status "disputed" and explain in the comment that the quote has multiple
    individual authors, which this platform cannot verify as a single-author
    quote.
    """
  end

  defp quote_correction_instructions(false) do
    """
    Correction mode is disabled for this verification. Do not return corrected
    quote fields. Judge only whether the current stored quote is authentic and
    correctly attributed.
    """
  end

  defp status_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "status" => %{type: "string", enum: @statuses},
        "comment" => %{type: "string", description: "Short justification with evidence."}
      },
      required: ["status", "comment"]
    }
  end

  defp quote_status_schema(false), do: status_schema()

  defp quote_status_schema(true) do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "status" => %{type: "string", enum: @statuses},
        "comment" => %{type: "string", description: "Short justification with evidence."},
        "correction" => %{
          type: ["object", "null"],
          description:
            "Correct values to apply before re-verifying. Use null when the stored quote fields are already right or no reliable correction is available.",
          additionalProperties: false,
          properties: %{
            "content" => %{
              type: "string",
              description:
                "Correct exact quote text, verbatim or faithfully translated. Do not include surrounding quotation marks."
            },
            "source_url" => %{
              type: "string",
              description: "Reliable source URL that contains the exact quote and attribution."
            },
            "date" => %{
              type: "string",
              description:
                "Correct quote/source date. Use YYYY-MM-DD, YYYY-MM, or YYYY to match date_precision."
            },
            "date_precision" => %{
              type: "string",
              description: "Precision of the date field.",
              enum: ["day", "month", "year"]
            },
            "author" => %{
              type: "object",
              additionalProperties: false,
              properties: %{
                "name" => %{
                  type: "string",
                  description:
                    "One corrected author name only: a single individual, or the organisation name when the organisation speaks for itself. Never return a combined list of people."
                },
                "bio" => %{type: "string", description: "Author bio, max 7 words."},
                "wikipedia_url" => %{type: "string", description: "Author Wikipedia page URL."},
                "twitter_username" => %{
                  type: "string",
                  description: "Author Twitter/X handle without @."
                }
              },
              required: ["name", "bio", "wikipedia_url", "twitter_username"]
            }
          },
          required: ["content", "source_url", "date", "date_precision", "author"]
        }
      },
      required: ["status", "comment", "correction"]
    }
  end

  defp answer_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "correct_answer" => %{type: "string", enum: @answers},
        "comment" => %{
          type: "string",
          description: "Short justification with the quote's wording."
        }
      },
      required: ["correct_answer", "comment"]
    }
  end

  # --- OpenAI plumbing (mirrors QuotatorAI) ----------------------------------

  defp ask_gpt(prompt, schema, name, system, web_search?) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "Missing OPENAI_API_KEY"}
    else
      url = "https://api.openai.com/v1/responses"

      body =
        %{
          "model" => to_string(@model),
          "reasoning" => %{"effort" => "high"},
          "text" => %{
            "format" => %{
              "name" => name,
              "type" => "json_schema",
              "schema" => schema
            }
          },
          "background" => true,
          "input" => [
            %{"role" => "system", "content" => system},
            %{
              "role" => "user",
              "content" =>
                "Return one JSON object strictly conforming to the provided JSON Schema."
            },
            %{"role" => "user", "content" => prompt}
          ]
        }
        |> maybe_put_web_search(web_search?)

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

  # Only quote-authenticity checks need to browse for primary sources; relevance
  # and vote-answer checks are judged from the quote text and statement alone.
  defp maybe_put_web_search(body, true) do
    body
    |> Map.put("tools", [%{"type" => "web_search"}])
    |> Map.put("tool_choice", "auto")
  end

  defp maybe_put_web_search(body, false), do: body

  defp extract_job_id(%{"id" => id}), do: {:ok, id}
  defp extract_job_id(_), do: {:error, "No Job ID found"}

  defp process_completed_job(resp) do
    content = Map.get(resp, "output_text") || extract_output_text(resp)

    decoded =
      case content && Jason.decode(content) do
        {:ok, decoded} when is_map(decoded) -> decoded
        _ -> %{}
      end

    Map.put(decoded, "model", Map.get(resp, "model") || to_string(@model))
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

  defp truncate_body(body) when is_binary(body) and byte_size(body) > 500 do
    binary_part(body, 0, 500) <> "…"
  end

  defp truncate_body(body), do: body
end
