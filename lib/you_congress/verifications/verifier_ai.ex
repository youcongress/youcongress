defmodule YouCongress.Verifications.VerifierAI do
  @moduledoc """
  OpenAI-backed implementation of `YouCongress.Verifications.Verifier`.

  Uses the OpenAI Responses API in `background` mode with `web_search` so the
  model can check primary sources, exactly like
  `YouCongress.Opinions.Quotes.QuotatorAI`. `submit/2` starts a background job and
  returns its id; `check_job_status/1` polls it and returns the parsed result.

  Result maps (string keys):
  - `:quote` / `:relevance` -> `%{"status" => ..., "comment" => ..., "model" => ...}`
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
    with {:ok, %{prompt: prompt, schema: schema, name: name, system: system} = spec} <-
           build(subject_type, subject),
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

  defp build(:quote, %Opinion{} = opinion) do
    opinion = Repo.preload(opinion, :author)
    author = opinion.author && opinion.author.name

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
    author, and that the source URL (or another reliable source) contains it.

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
       schema: status_schema(),
       name: "QuoteVerification",
       web_search: true,
       system:
         "You are a meticulous fact-checker. You only confirm a quote when a reliable source contains the exact text and attributes it to the author."
     }}
  end

  defp build(:relevance, %OpinionStatement{} = opinion_statement) do
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

  defp build(:vote, %Vote{} = vote) do
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

    Based only on what the quote actually says, what is the author's position on
    the whole statement? Answer with exactly one of:
    - "for": the quote clearly supports the statement.
    - "against": the quote clearly opposes the statement.
    - "abstain": the quote is explicitly neutral/undecided on the statement.
    - "none": the quote does not make the author's position on the statement clear.
    Always include a short comment justifying the answer with the quote's wording.
    """

    {:ok,
     %{
       prompt: prompt,
       schema: answer_schema(),
       name: "VoteVerification",
       system:
         "You classify an author's stance on a statement strictly from a quote. Choose \"none\" unless the quote makes the stance unambiguous."
     }}
  end

  defp build(_subject_type, _subject), do: {:error, :invalid_subject}

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
