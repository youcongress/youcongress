defmodule YouCongress.Statements.SynthesisAI do
  @moduledoc """
  OpenAI-backed implementation of `YouCongress.Statements.Synthesis`.

  Uses the OpenAI Responses API in `background` mode, like
  `YouCongress.Verifications.VerifierAI` but without web_search: the synthesis
  must be grounded exclusively in the quotes we send. `submit/2` starts a
  background job and returns its id; `check_job_status/1` polls it and returns
  the decoded synthesis map.
  """

  @behaviour YouCongress.Statements.Synthesis

  require Logger

  alias YouCongress.Authors.Author
  alias YouCongress.Opinions.Opinion

  @model :"gpt-5.4"
  @timeout_in_min 120
  @max_quotes_in_prompt 150
  @min_quotes_per_stance 5
  @max_content_chars 500
  @max_bio_chars 120

  @system_message "You are a neutral policy analyst synthesizing sourced quotes about a debate " <>
                    "statement for YouCongress. Ground every claim exclusively in the quotes " <>
                    "provided. Never introduce outside facts, events, statistics, or names. " <>
                    "Never invent, alter, or paraphrase quote text as if quoting. Cite quotes " <>
                    "only by their opinion_id, using only ids present in the input. Write in " <>
                    "English, in plain text (no markdown), in a measured, non-partisan tone " <>
                    "that presents the strongest version of each side."

  @impl true
  def submit(statement, votes) do
    with {:ok, data} <- ask_gpt(prompt(statement, votes)),
         {:ok, job_id} <- extract_job_id(data) do
      {:ok, job_id}
    end
  end

  @doc false
  # Public so tests can cover the sampling/serialization and so the exact
  # prompt can be inspected in iex when tuning.
  def prompt(statement, votes) do
    pairs = quote_stance_pairs(votes)
    selected = select_quotes(pairs)
    build_prompt(statement.title, selected, length(pairs))
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

  # --- Quote serialization ----------------------------------------------------

  # Each vote carries the author's main opinion plus any alternate sourced
  # quotes for the same statement; all of them share the vote's answer.
  defp quote_stance_pairs(votes) do
    votes
    |> Enum.flat_map(fn vote ->
      [vote.opinion | List.wrap(vote.alternate_opinions)]
      |> Enum.filter(&match?(%Opinion{}, &1))
      |> Enum.map(&{&1, vote.answer})
    end)
    |> Enum.uniq_by(fn {opinion, _stance} -> opinion.id end)
  end

  # Keep at most @max_quotes_in_prompt quotes, allocating proportionally per
  # stance with a minimum per non-empty stance so minority positions always
  # reach the model. Lists are pre-ordered best-first by the votes query.
  defp select_quotes(pairs) when length(pairs) <= @max_quotes_in_prompt, do: pairs

  defp select_quotes(pairs) do
    grouped = Enum.group_by(pairs, fn {_opinion, stance} -> stance end)
    total = length(pairs)

    quotas =
      Map.new(grouped, fn {stance, list} ->
        proportional = floor(length(list) / total * @max_quotes_in_prompt)
        {stance, min(length(list), max(@min_quotes_per_stance, proportional))}
      end)

    quotas = trim_quotas(quotas, Enum.sum(Map.values(quotas)) - @max_quotes_in_prompt)

    Enum.flat_map(grouped, fn {stance, list} -> Enum.take(list, quotas[stance]) end)
  end

  # The per-stance minimums can push the total over budget; shrink the largest
  # buckets first until it fits.
  defp trim_quotas(quotas, excess) when excess <= 0, do: quotas

  defp trim_quotas(quotas, excess) do
    {stance, _quota} = Enum.max_by(quotas, fn {_stance, quota} -> quota end)
    trim_quotas(Map.update!(quotas, stance, &(&1 - 1)), excess - 1)
  end

  defp serialize_quote({%Opinion{} = opinion, stance}) do
    author = loaded_author(opinion)

    %{
      "opinion_id" => opinion.id,
      "author" => (author && author.name) || "Unknown",
      "stance" => to_string(stance),
      "quote" => truncate_text(opinion.content, @max_content_chars)
    }
    |> maybe_put("bio", author && truncate_text(author.bio || author.description, @max_bio_chars))
    |> maybe_put("date", Opinion.display_date(opinion))
    |> Jason.encode!()
  end

  defp loaded_author(%Opinion{author: %Author{} = author}), do: author
  defp loaded_author(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truncate_text(nil, _max), do: nil

  defp truncate_text(text, max) when is_binary(text) do
    if String.length(text) <= max do
      text
    else
      String.slice(text, 0, max) <> " […]"
    end
  end

  # --- Prompt -----------------------------------------------------------------

  defp build_prompt(title, selected_pairs, total) do
    included = length(selected_pairs)

    sample_note =
      if included < total, do: " (a representative sample of #{total} in total)", else: ""

    quote_lines = Enum.map_join(selected_pairs, "\n", &serialize_quote/1)

    """
    Statement: #{title}

    Below are #{included} sourced quotes from public figures about this statement#{sample_note}.
    Each line is a JSON object with: opinion_id, author, bio (when known), stance
    (the author's recorded vote: for/against/abstain), date (when known), and
    quote (possibly truncated).

    #{quote_lines}

    Write a synthesis of this debate:

    1. headline: ONE sentence (max ~30 words) capturing the main takeaway — where
       the crux of agreement or disagreement lies. Do not include vote counts or
       percentages; the page shows exact tallies separately.
    2. arguments_for / arguments_against: 2-5 clusters each of DISTINCT lines of
       argument. middle_ground: 0-5 clusters for genuinely conditional, nuanced,
       or explicitly undecided positions — return an empty array rather than
       inventing one.
       Each cluster:
       - title: a short neutral label for the argument (not a slogan, not a
         person's name)
       - summary: 1-3 sentences stating the argument as its proponents make it,
         without endorsing or rebutting it, using only content present in the
         quotes
       - opinion_ids: 1-6 ids of quotes that best represent this cluster. Prefer
         clear, substantive, recent quotes from diverse authors. A quote's
         cluster must match what that quote actually argues; use its stance
         field as a strong prior.
    3. insights: up to 5 one-sentence cross-cutting observations strictly
       derivable from the quotes — e.g. points where opposing sides agree,
       differing definitions or timeframes behind the disagreement, or patterns
       across author backgrounds visible in the bios.
    4. conclusion: 2-3 sentences on the overall state of the debate. Neutral; no
       verdict on who is right; no vote counts.

    Rules: represent each side by its strongest arguments regardless of how many
    quotes it has; if material for a section is missing, keep it minimal or empty
    rather than padding; every opinion_id you output must be one of the ids
    above; English only; plain text only (no markdown).
    """
  end

  # --- JSON schema --------------------------------------------------------------

  defp cluster_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "title" => %{
          type: "string",
          description: "Short neutral label for this line of argument (max ~8 words)."
        },
        "summary" => %{
          type: "string",
          description:
            "1-3 sentences summarizing the argument as its proponents make it, grounded only in the provided quotes."
        },
        "opinion_ids" => %{
          type: "array",
          minItems: 1,
          maxItems: 6,
          items: %{type: "integer"},
          description:
            "opinion_id values of the provided quotes that best represent this argument. Only ids from the input."
        }
      },
      required: ["title", "summary", "opinion_ids"]
    }
  end

  defp json_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "headline" => %{
          type: "string",
          description:
            "One sentence, max ~30 words: the main takeaway of the debate. No vote counts."
        },
        "arguments_for" => %{
          type: "array",
          minItems: 0,
          maxItems: 5,
          items: cluster_schema()
        },
        "arguments_against" => %{
          type: "array",
          minItems: 0,
          maxItems: 5,
          items: cluster_schema()
        },
        "middle_ground" => %{
          type: "array",
          minItems: 0,
          maxItems: 5,
          items: cluster_schema()
        },
        "insights" => %{
          type: "array",
          minItems: 0,
          maxItems: 5,
          items: %{type: "string"}
        },
        "conclusion" => %{
          type: "string",
          description:
            "2-3 neutral sentences on the state of the debate. No verdict, no vote counts."
        }
      },
      required: [
        "headline",
        "arguments_for",
        "arguments_against",
        "middle_ground",
        "insights",
        "conclusion"
      ]
    }
  end

  # --- OpenAI plumbing (mirrors VerifierAI, without web_search) ----------------

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
            "name" => "QuoteSynthesis",
            "type" => "json_schema",
            "schema" => json_schema()
          }
        },
        "background" => true,
        "input" => [
          %{"role" => "system", "content" => @system_message},
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
