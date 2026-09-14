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

  alias YouCongress.Repo
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Verifications.KeyIdeaCoverage
  alias YouCongress.Votes.Vote

  @model :"gpt-5.4-mini"
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
    Source passage (provided by the submitter because the source may be a book,
    PDF, or paywalled article that is not fetchable on the open web):
    \"\"\"
    #{opinion.source_text || "None provided"}
    \"\"\"
    Quote:
    \"\"\"
    #{opinion.content}
    \"\"\"

    Using web_search, confirm the quote is real and verbatim (allowing [...] for
    omitted text and faithful translation), that it is correctly attributed to the
    author, and that the source URL contains it. When no fetchable source URL is
    available but a source passage is provided above, verify the quote against that
    passage instead: it is authentic when the quote appears in, or is a faithful
    rendering/translation of, the provided passage and the passage attributes it to
    the author. The provided passage replaces the web fetch you cannot perform for
    such sources; still use web_search to corroborate the attribution where you can.
    Treat named declarations, manifestos, open letters, petitions, collective
    statements, and similar documents as valid quote authors when the source
    presents the quoted text as the wording of that document, even if the document
    has many signers or a broad coalition behind it. Do not dispute a quote merely
    because the author is a document title rather than a single person or
    organisation.

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
    Verify whether the following quote covers every material key idea of the
    COMPLETE statement and makes the author's stance determinable. This relevance
    pass should not decide the final vote direction; the separate vote pass does.

    Statement: #{statement.title}
    Source URL: #{opinion.source_url || "None provided"}
    Source passage (for non-web sources): #{opinion.source_text || "None provided"}
    Quote:
    \"\"\"
    #{opinion.content}
    \"\"\"

    #{KeyIdeaCoverage.prompt_instructions()}

    When a Source URL is provided, use web_search to inspect the source page when
    the quote is abstract, uses shorthand, or refers to "the proposal", "this",
    "these ideas", or similar context-dependent language. When no Source URL is
    provided, use the Source passage above as the cited source context for the
    same purpose (the source may be a book, PDF, or paywalled article that cannot
    be fetched on the open web).

    Source context may identify what a pronoun or shorthand phrase in the quote
    refers to, but the quoted words must still express every material proposition.
    Do not accept a quote merely because the article discusses a missing idea.
    Do not infer a position from general sentiment, party membership, job title,
    institutional role, or facts outside the quote.

    Choose a status:
    - "ai_verified": every material key idea is covered by the quote and a stance
      on the COMPLETE statement is determinable.
    - "disputed": at least one material key idea is missing, the quote is merely
      adjacent, or no stance on the COMPLETE statement is determinable.
    - "ai_unverifiable": you cannot tell.
    Always include a short comment explaining your decision.
    """

    {:ok,
     %{
       prompt: prompt,
       schema: relevance_status_schema(),
       name: "RelevanceVerification",
       web_search: true,
       system:
         "Verify relevance only when the quote itself covers every material key idea of the COMPLETE statement. Source context may resolve a referent but cannot supply a missing idea. Reject broader, narrower, and merely adjacent claims."
     }}
  end

  defp build(:vote, %Vote{} = vote, _opts) do
    vote = Repo.preload(vote, [:opinion, :statement])
    opinion = vote.opinion
    statement = vote.statement

    prompt = """
    Determine the author's position on the statement from the quote itself. Use
    the cited source only to verify wording or resolve genuine shorthand.

    Statement: #{statement.title}
    Source URL: #{(opinion && opinion.source_url) || "None provided"}
    Source passage (for non-web sources): #{(opinion && opinion.source_text) || "None provided"}
    Quote:
    \"\"\"
    #{opinion && opinion.content}
    \"\"\"

    Current recorded answer: #{vote.answer}

    Before classifying a vote, apply this relevance gate:
    #{KeyIdeaCoverage.prompt_instructions()}
    When a Source URL is provided, use web_search to inspect the source only to
    verify the quote and resolve genuine shorthand. Do not use surrounding text
    to add a material proposition absent from the quote.

    Answer with exactly one of:
    - "for": the quote explicitly or strongly implies support for the statement.
    - "against": the quote explicitly or strongly implies opposition to the
      statement.
    - "abstain": the quote is explicitly neutral/undecided on the statement.
    - "none": any material key idea is missing, or the quote is genuinely
      ambiguous or merely adjacent to the issue.
    Always include a short comment justifying the answer with the quote's wording
    and, when used to resolve shorthand, the cited source context. If the position is implied rather
    than explicit in the stored quote, identify that inference and any limitation
    in the evidence.
    """

    {:ok,
     %{
       prompt: prompt,
       schema: answer_schema(),
       name: "VoteVerification",
       web_search: true,
       system:
         "Classify a vote only after the quote itself covers every material key idea of the COMPLETE statement. Source context may resolve shorthand but cannot supply a missing idea. Return none whenever coverage is incomplete."
     }}
  end

  defp build(_subject_type, _subject, _opts), do: {:error, :invalid_subject}

  defp quote_correction_instructions(true) do
    """
    Also check whether the stored content, date, source, and author are the
    right canonical values. If the quote is authentic but any stored field is
    wrong and you can recover the right values from reliable evidence, return
    status "disputed" and include a correction object with the proper content,
    source_url, source_text, date, date_precision, and author metadata. Provide
    source_url for web sources and source_text for non-web sources (book, PDF,
    paywalled article); set the one that does not apply to null. Use null
    correction when no correction should be applied.

    For author corrections, return exactly one author name only when the quote has
    one individual author, when an organisation is speaking on its own behalf, or
    when the source presents the quote as the text of one named document such as a
    declaration, manifesto, open letter, petition, joint statement, report, or
    similar collective text. In the document case, use the document title (or the
    named issuing coalition if that is the canonical attribution) as the author,
    and use month/year date precision if exact dates conflict.

    If a source merely lists multiple individual authors/signers and does not
    present a single organisation, coalition, or named document as the quoted
    author, do not return a correction. Return status "disputed" and explain in
    the comment that the quote has multiple individual authors, which this
    platform cannot verify as a single-author quote.
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

  defp relevance_status_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties:
        Map.merge(
          %{
            "status" => %{type: "string", enum: @statuses},
            "comment" => %{type: "string", description: "Short justification with evidence."}
          },
          coverage_properties()
        ),
      required: [
        "status",
        "comment",
        "all_key_ideas_covered",
        "key_idea_coverage",
        "missing_key_ideas"
      ]
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
              type: ["string", "null"],
              description:
                "Reliable source URL that contains the exact quote and attribution. Use null for non-web sources (books, PDFs, paywalled articles) that have no public URL."
            },
            "source_text" => %{
              type: ["string", "null"],
              description:
                "For non-web sources, the corrected citation plus the surrounding passage that contains the quote (e.g. book title, author, edition, page, then the passage). Use null when the source is a web URL."
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
                    "One corrected author name only: a single individual, the organisation name when the organisation speaks for itself, or a named declaration/manifesto/open letter/petition/joint statement/report title when the source presents the quote as that document's text. Never return a combined list of people."
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
          required: [
            "content",
            "source_url",
            "source_text",
            "date",
            "date_precision",
            "author"
          ]
        }
      },
      required: ["status", "comment", "correction"]
    }
  end

  defp answer_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties:
        Map.merge(
          %{
            "correct_answer" => %{type: "string", enum: @answers},
            "comment" => %{
              type: "string",
              description: "Short justification with the quote's wording."
            }
          },
          coverage_properties()
        ),
      required: [
        "correct_answer",
        "comment",
        "all_key_ideas_covered",
        "key_idea_coverage",
        "missing_key_ideas"
      ]
    }
  end

  defp coverage_properties do
    %{
      "all_key_ideas_covered" => %{
        type: "boolean",
        description:
          "True only when every material idea in the statement is covered by the quote."
      },
      "key_idea_coverage" => %{
        type: "array",
        minItems: 0,
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
      },
      "missing_key_ideas" => %{
        type: "array",
        items: %{type: "string"},
        description:
          "Every material statement idea not expressed by the quote; empty only on a pass."
      }
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

  # Quote authenticity needs primary-source browsing. Relevance and vote-answer
  # checks use browsing only to verify wording and resolve genuine shorthand.
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
