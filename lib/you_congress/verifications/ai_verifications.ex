defmodule YouCongress.Verifications.AIVerifications do
  @moduledoc """
  Turns a completed LLM verification result into a stored verification and drives
  the next stage of the pipeline.

  Cascade:
  - `quote` positive  -> verify the relevance of each of the quote's statement links.
  - `relevance` positive -> verify each vote that cites the quote on that statement.
  - `relevance` disputed -> unlink the quote from the statement.
  - `vote` -> set the vote's answer to whichever of for/against/abstain the quote
    actually supports (if any) and mark it ai_verified; otherwise mark it
    ai_unverifiable.

  All verifications are owned by the configured `:verification_user_id`
  (an admin/moderator). When it is unset, this module logs and no-ops so dev and
  tests never crash.
  """

  import Ecto.Query, warn: false

  require Logger

  alias YouCongress.Repo
  alias YouCongress.Authors
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Statements
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Verifications.QuoteCorrectionLoop
  alias YouCongress.Verifications
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.VoteVerifications
  alias YouCongress.VerificationStatus
  alias YouCongress.Workers.VerificationWorker

  @allowed_statuses ~w(ai_verified ai_unverifiable disputed unverifiable unverified)
  @status_aliases %{"verified" => "ai_verified"}
  @answers ~w(for against abstain)

  @doc """
  Record the verification for `subject`/`id` from a completed LLM `result` and
  cascade to the next stage. `subject` is `"quote"`, `"relevance"` or `"vote"`.
  """
  @spec record_and_cascade(String.t(), integer(), map(), map()) :: :ok
  def record_and_cascade(subject, id, result, opts \\ %{}) do
    case system_user_id() do
      nil ->
        Logger.warning(
          "verification_user_id not configured; skipping #{subject} verification for ##{id}"
        )

        :ok

      user_id ->
        do_record(subject, id, result, model(result), user_id, opts)
    end
  end

  defp do_record("quote", opinion_id, result, model, user_id, opts) do
    status = normalize_status(result["status"])

    if QuoteCorrectionLoop.allow_correction?(opts) do
      case maybe_apply_quote_correction(
             opinion_id,
             result,
             QuoteCorrectionLoop.next_attempt(opts)
           ) do
        :updated ->
          :ok

        :unchanged ->
          record_quote_verification(opinion_id, status, result, model, user_id)

        {:error, reason} ->
          Logger.error("Failed to apply quote correction for ##{opinion_id}: #{inspect(reason)}")

          record_quote_verification(opinion_id, status, result, model, user_id)
      end
    else
      record_quote_verification(opinion_id, status, result, model, user_id)
    end
  end

  defp do_record("relevance", opinion_statement_id, result, model, user_id, _opts) do
    status = normalize_status(result["status"])

    case Repo.get(OpinionStatement, opinion_statement_id) do
      nil ->
        :ok

      %OpinionStatement{} = opinion_statement when status == :disputed ->
        # A disputed relevance means the quote does not back this statement: unlink it.
        Logger.info(
          "Unlinking opinion #{opinion_statement.opinion_id} from statement " <>
            "#{opinion_statement.statement_id}: #{comment(result)}"
        )

        unlink(opinion_statement)

      %OpinionStatement{} = opinion_statement ->
        attrs = %{
          opinion_statement_id: opinion_statement_id,
          status: status,
          comment: comment(result),
          model: model,
          user_id: user_id
        }

        case OpinionStatementVerifications.create_verification(attrs) do
          {:ok, _} ->
            if VerificationStatus.positive?(status), do: enqueue_votes(opinion_statement)
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to record relevance verification for ##{opinion_statement_id}: #{inspect(reason)}"
            )

            :ok
        end
    end
  end

  defp do_record("vote", vote_id, result, model, user_id, opts) do
    case Repo.get(Vote, vote_id) do
      nil ->
        :ok

      %Vote{} = vote ->
        correct_answer = normalize_answer(result["correct_answer"])
        opinion_id = explicit_opinion_id(opts) || vote.opinion_id

        attrs = %{
          vote_id: vote_id,
          opinion_id: opinion_id,
          comment: comment(result),
          model: model,
          user_id: user_id
        }

        if correct_answer do
          # If the quote supports a different answer, correct the vote, then verify.
          if to_string(vote.answer) != correct_answer do
            Votes.update_vote(vote, %{answer: correct_answer})
          end

          create_vote_verification(Map.put(attrs, :status, :ai_verified), vote_id)
        else
          create_vote_verification(Map.put(attrs, :status, :ai_unverifiable), vote_id)
        end
    end
  end

  defp record_quote_verification(opinion_id, status, result, model, user_id) do
    attrs = %{
      opinion_id: opinion_id,
      status: status,
      comment: comment(result),
      model: model,
      user_id: user_id
    }

    case Verifications.create_verification(attrs) do
      {:ok, _} ->
        if VerificationStatus.positive?(status), do: enqueue_relevance(opinion_id)
        :ok

      {:error, reason} ->
        Logger.error("Failed to record quote verification for ##{opinion_id}: #{inspect(reason)}")
        :ok
    end
  end

  defp create_vote_verification(attrs, vote_id) do
    case VoteVerifications.create_verification(attrs) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to record vote verification for ##{vote_id}: #{inspect(reason)}")
        :ok
    end
  end

  # --- Cascade helpers --------------------------------------------------------

  defp enqueue_relevance(opinion_id) do
    from(os in OpinionStatement, where: os.opinion_id == ^opinion_id, select: os.id)
    |> Repo.all()
    |> Enum.each(&enqueue("relevance", &1))
  end

  defp enqueue_votes(%OpinionStatement{opinion_id: opinion_id, statement_id: statement_id}) do
    case Opinions.get_opinion(opinion_id) do
      %Opinion{author_id: author_id} when not is_nil(author_id) ->
        from(v in Vote,
          where: v.author_id == ^author_id and v.statement_id == ^statement_id,
          select: v.id
        )
        |> Repo.all()
        |> Enum.each(&enqueue("vote", &1, opinion_id: opinion_id))

      _ ->
        :ok
    end
  end

  defp enqueue(subject, id, opts \\ []) do
    %{"subject" => subject, "id" => id}
    |> maybe_put_arg("opinion_id", opts[:opinion_id])
    |> VerificationWorker.new()
    |> Oban.insert()
  end

  defp maybe_put_arg(args, _key, nil), do: args
  defp maybe_put_arg(args, key, value), do: Map.put(args, key, value)

  defp unlink(%OpinionStatement{opinion_id: opinion_id, statement_id: statement_id}) do
    opinion = Opinions.get_opinion(opinion_id)
    statement = Statements.get_statement(statement_id)

    if opinion && statement do
      Opinions.remove_opinion_from_statement(opinion, statement)
    end

    :ok
  end

  # --- Result parsing ---------------------------------------------------------

  defp maybe_apply_quote_correction(opinion_id, result, next_correction_attempt) do
    with %Opinion{} = opinion <- Opinions.get_opinion(opinion_id),
         {:ok, attrs} <- correction_attrs(result) do
      apply_quote_correction(opinion, attrs, next_correction_attempt)
    else
      nil -> :unchanged
      :no_correction -> :unchanged
      {:error, _reason} = error -> error
    end
  end

  defp correction_attrs(result) do
    correction = quote_correction(result)

    attrs =
      %{}
      |> maybe_put_string(:content, first_present(correction, ["content", "quote"]))
      |> maybe_put_string(:source_url, first_present(correction, ["source_url"]))
      |> maybe_put_string(:date, first_present(correction, ["date"]))
      |> maybe_put_string(:date_precision, first_present(correction, ["date_precision"]))

    with {:ok, attrs} <- maybe_put_corrected_author(attrs, correction) do
      if map_size(attrs) == 0, do: :no_correction, else: {:ok, attrs}
    end
  end

  defp quote_correction(%{"correction" => correction}) when is_map(correction), do: correction
  defp quote_correction(%{"correction" => nil}), do: %{}
  defp quote_correction(result) when is_map(result), do: result
  defp quote_correction(_), do: %{}

  defp apply_quote_correction(%Opinion{} = opinion, attrs, next_correction_attempt) do
    changeset = Opinions.change_opinion(opinion, attrs)

    cond do
      not changeset.valid? ->
        {:error, changeset}

      map_size(changeset.changes) == 0 ->
        :unchanged

      true ->
        case Opinions.update_opinion(opinion, attrs, correction_attempts: next_correction_attempt) do
          {:ok, _opinion} ->
            Logger.info("Applied AI quote correction for opinion #{opinion.id}; re-verifying")
            :updated

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp maybe_put_corrected_author(attrs, correction) do
    case first_present(correction, ["author"]) do
      %{} = author_attrs ->
        with {:ok, author} <- upsert_author(author_attrs) do
          {:ok, Map.put(attrs, :author_id, author.id)}
        end

      _ ->
        {:ok, attrs}
    end
  end

  defp upsert_author(%{} = attrs) do
    normalized = normalize_author_attrs(attrs)

    cond do
      blank?(normalized["name"]) ->
        {:error, :invalid_author}

      not blank?(normalized["wikipedia_url"]) ->
        case Authors.find_by_wikipedia_url_or_create(normalized) do
          {:ok, author} -> {:ok, author}
          {:error, _} -> Authors.find_by_name_or_create(normalized)
        end

      true ->
        Authors.find_by_name_or_create(normalized)
    end
  end

  defp normalize_author_attrs(attrs) do
    %{
      "name" => clean_string(first_present(attrs, ["name"])),
      "bio" => clean_string(first_present(attrs, ["bio"])),
      "wikipedia_url" => normalize_wikipedia_url(first_present(attrs, ["wikipedia_url"])),
      "twitter_username" => normalize_twitter(first_present(attrs, ["twitter_username"])),
      "twin_origin" => false
    }
  end

  defp normalize_wikipedia_url(nil), do: nil

  defp normalize_wikipedia_url(url) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      trimmed -> String.replace(trimmed, ~r/https?:\/\/\w+\./, "https://en.")
    end
  end

  defp normalize_wikipedia_url(_), do: nil

  defp normalize_twitter(nil), do: nil
  defp normalize_twitter(""), do: nil
  defp normalize_twitter("@" <> handle), do: clean_string(handle)
  defp normalize_twitter("https://x.com/" <> handle), do: clean_string(handle)
  defp normalize_twitter("https://twitter.com/" <> handle), do: clean_string(handle)
  defp normalize_twitter(handle) when is_binary(handle), do: clean_string(handle)
  defp normalize_twitter(_), do: nil

  defp first_present(map, keys) when is_map(map) do
    Enum.find_value(keys, fn key ->
      map
      |> Map.get(key)
      |> present_value()
    end)
  end

  defp first_present(_map, _keys), do: nil

  defp maybe_put_string(attrs, _key, nil), do: attrs
  defp maybe_put_string(attrs, key, value) when is_binary(value), do: Map.put(attrs, key, value)
  defp maybe_put_string(attrs, _key, _value), do: attrs

  defp present_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_value(value) when is_map(value), do: value
  defp present_value(value), do: value

  defp clean_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean_string(_), do: nil

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp normalize_status(status) when is_binary(status) do
    normalized = Map.get(@status_aliases, status, status)

    if normalized in @allowed_statuses,
      do: String.to_existing_atom(normalized),
      else: :ai_unverifiable
  end

  defp normalize_status(_), do: :ai_unverifiable

  defp normalize_answer(answer) when is_binary(answer) do
    downcased = String.downcase(answer)
    if downcased in @answers, do: downcased, else: nil
  end

  defp normalize_answer(_), do: nil

  defp comment(result), do: result["comment"] || "AI verification"

  defp explicit_opinion_id(%{"opinion_id" => opinion_id}), do: normalize_id(opinion_id)
  defp explicit_opinion_id(%{opinion_id: opinion_id}), do: normalize_id(opinion_id)
  defp explicit_opinion_id(_opts), do: nil

  defp normalize_id(id) when is_integer(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
  defp normalize_id(_), do: nil

  # Never store "human" so resolve/1 treats it as an AI verification.
  defp model(result) do
    case result["model"] do
      model when is_binary(model) and model != "" and model != "human" -> model
      _ -> "ai"
    end
  end

  defp system_user_id do
    case Application.get_env(:you_congress, :verification_user_id) do
      nil -> nil
      "" -> nil
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
    end
  end
end
