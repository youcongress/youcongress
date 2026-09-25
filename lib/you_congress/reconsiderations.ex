defmodule YouCongress.Reconsiderations do
  @moduledoc """
  Creator-led before-and-after voting experiences.

  A participant's current position continues to live in `votes`. This context stores the
  self-reported before/after pair so campaign results remain historically stable.
  """

  import Ecto.Query, warn: false

  alias YouCongress.Accounts.User
  alias YouCongress.Authors.Author
  alias YouCongress.Delegations

  alias YouCongress.Reconsiderations.{
    Delegate,
    DelegateSelection,
    Reconsideration,
    ReconsiderationStatement,
    Response
  }

  alias YouCongress.Repo
  alias YouCongress.Statements.Statement
  alias YouCongress.Votes

  @answers [:for, :against, :abstain]

  def get_reconsideration_by_slug!(slug) do
    Reconsideration
    |> Repo.get_by!(slug: slug, published: true)
    |> preload_experience()
  end

  def get_reconsideration_by_username_and_slug!(username, slug) do
    username = String.downcase(username)

    Reconsideration
    |> join(:inner, [reconsideration], creator in assoc(reconsideration, :creator))
    |> where(
      [reconsideration, creator],
      reconsideration.slug == ^slug and reconsideration.published == true and
        fragment("lower(?)", creator.username) == ^username
    )
    |> Repo.one!()
    |> preload_experience()
  end

  def get_reconsideration!(id) do
    Reconsideration
    |> Repo.get!(id)
    |> preload_experience()
  end

  def change_reconsideration(%Reconsideration{} = reconsideration, attrs \\ %{}) do
    Reconsideration.changeset(reconsideration, attrs)
  end

  def create_from_refs(%User{} = user, attrs) do
    with {:ok, statements} <- resolve_statement_refs(attrs["statement_refs"]),
         {:ok, delegates} <- resolve_author_refs(attrs["delegate_refs"]),
         :ok <- validate_statement_count(statements) do
      create_reconsideration(
        user,
        Map.drop(attrs, ["statement_refs", "delegate_refs"]),
        Enum.map(statements, & &1.id),
        Enum.map(delegates, & &1.id)
      )
    end
  end

  def create_reconsideration(%User{} = user, attrs, statement_ids, delegate_ids) do
    statement_ids =
      statement_ids |> Enum.map(&normalize_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    delegate_ids =
      delegate_ids |> Enum.map(&normalize_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    statements = records_in_order(Statement, statement_ids)
    delegates = records_in_order(Author, delegate_ids)

    with :ok <- validate_statement_count(statements),
         true <- length(statements) == length(statement_ids),
         true <- length(delegates) == length(delegate_ids) do
      attrs =
        attrs
        |> Map.new()
        |> Map.put("creator_id", user.author_id)
        |> Map.put_new("published", true)
        |> Map.put("slug", unique_slug(attrs["title"] || attrs[:title]))

      Repo.transaction(fn ->
        reconsideration =
          %Reconsideration{}
          |> Reconsideration.changeset(attrs)
          |> insert_or_rollback()

        statements
        |> Enum.with_index()
        |> Enum.each(fn {statement, position} ->
          %ReconsiderationStatement{}
          |> ReconsiderationStatement.changeset(%{
            reconsideration_id: reconsideration.id,
            statement_id: statement.id,
            statement_title: statement.title,
            position: position
          })
          |> insert_or_rollback()
        end)

        delegates
        |> Enum.with_index()
        |> Enum.each(fn {author, position} ->
          %Delegate{}
          |> Delegate.changeset(%{
            reconsideration_id: reconsideration.id,
            author_id: author.id,
            position: position
          })
          |> insert_or_rollback()
        end)

        get_reconsideration!(reconsideration.id)
      end)
      |> unwrap_transaction()
    else
      false -> {:error, "One or more statements or people could not be found."}
      {:error, _reason} = error -> error
    end
  end

  def submit_response(
        %Reconsideration{} = reconsideration,
        %User{} = user,
        responses,
        delegate_ids
      ) do
    statement_ids = Enum.map(reconsideration.reconsideration_statements, & &1.statement_id)
    allowed_delegate_ids = Enum.map(reconsideration.delegates, & &1.author_id)

    with {:ok, normalized_responses} <- normalize_responses(responses),
         :ok <- validate_response_statements(normalized_responses, statement_ids),
         {:ok, normalized_delegate_ids} <- normalize_delegate_ids(delegate_ids),
         :ok <- validate_delegates(normalized_delegate_ids, allowed_delegate_ids),
         false <- participated?(reconsideration.id, user.author_id) do
      normalized_delegate_ids = Enum.reject(normalized_delegate_ids, &(&1 == user.author_id))

      Repo.transaction(fn ->
        persist_response(reconsideration, user, normalized_responses, normalized_delegate_ids)
      end)
      |> unwrap_transaction()
    else
      true -> {:error, :already_submitted}
      {:error, _reason} = error -> error
    end
  end

  defp persist_response(reconsideration, user, responses, delegate_ids) do
    saved_responses = Enum.map(responses, &persist_answer(reconsideration, user, &1))
    Enum.each(responses, &persist_vote(user, &1))
    Enum.each(delegate_ids, &persist_delegate_selection(reconsideration, user, &1))
    saved_responses
  end

  defp persist_answer(reconsideration, user, {statement_id, answers}) do
    %Response{}
    |> Response.changeset(%{
      reconsideration_id: reconsideration.id,
      statement_id: statement_id,
      author_id: user.author_id,
      before_answer: answers.before,
      after_answer: answers.after
    })
    |> insert_or_rollback()
  end

  defp persist_vote(user, {statement_id, answers}) do
    case Votes.create_or_update(%{
           statement_id: statement_id,
           answer: answers.after,
           author_id: user.author_id,
           user_id: user.id,
           direct: true
         }) do
      {:ok, _vote} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_delegate_selection(reconsideration, user, delegate_id) do
    %DelegateSelection{}
    |> DelegateSelection.changeset(%{
      reconsideration_id: reconsideration.id,
      participant_author_id: user.author_id,
      delegate_author_id: delegate_id
    })
    |> insert_or_rollback()

    unless Delegations.delegating?(user.author_id, delegate_id) do
      case Delegations.create_delegation(user, delegate_id) do
        {:ok, _delegation} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  def submit_pending(%User{} = user, %{"slug" => slug} = payload) do
    reconsideration = get_reconsideration_by_slug!(slug)

    submit_response(
      reconsideration,
      user,
      payload["responses"] || %{},
      payload["delegate_ids"] || []
    )
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def participated?(reconsideration_id, author_id) do
    Repo.exists?(
      from r in Response,
        where: r.reconsideration_id == ^reconsideration_id and r.author_id == ^author_id
    )
  end

  def responses_for_author(reconsideration_id, author_id) do
    Repo.all(
      from r in Response,
        where: r.reconsideration_id == ^reconsideration_id and r.author_id == ^author_id,
        order_by: r.statement_id
    )
  end

  def stats(%Reconsideration{} = reconsideration) do
    base = from r in Response, where: r.reconsideration_id == ^reconsideration.id

    total_participants =
      base
      |> select([r], count(r.author_id, :distinct))
      |> Repo.one()

    changed_participants =
      base
      |> where([r], r.before_answer != r.after_answer)
      |> select([r], count(r.author_id, :distinct))
      |> Repo.one()

    per_statement =
      base
      |> group_by([r], r.statement_id)
      |> select([r], %{
        statement_id: r.statement_id,
        total: count(r.id),
        changed: filter(count(r.id), r.before_answer != r.after_answer)
      })
      |> Repo.all()
      |> Map.new(&{&1.statement_id, &1})

    transitions_by_statement =
      base
      |> group_by([r], [r.statement_id, r.before_answer, r.after_answer])
      |> select([r], %{
        statement_id: r.statement_id,
        before_answer: r.before_answer,
        after_answer: r.after_answer,
        count: count(r.id)
      })
      |> Repo.all()
      |> Enum.group_by(& &1.statement_id)

    delegate_counts =
      DelegateSelection
      |> where([selection], selection.reconsideration_id == ^reconsideration.id)
      |> group_by([selection], selection.delegate_author_id)
      |> select([selection], {selection.delegate_author_id, count(selection.id)})
      |> Repo.all()
      |> Map.new()

    statement_stats =
      Enum.map(reconsideration.reconsideration_statements, fn item ->
        counts = Map.get(per_statement, item.statement_id, %{total: 0, changed: 0})

        transitions =
          transitions_by_statement
          |> Map.get(item.statement_id, [])
          |> Enum.map(&Map.put(&1, :percent, percent(&1.count, counts.total)))
          |> Enum.sort_by(&transition_sort_key/1)

        %{
          statement_id: item.statement_id,
          title: item.statement_title,
          total: counts.total,
          changed: counts.changed,
          unchanged: counts.total - counts.changed,
          changed_percent: percent(counts.changed, counts.total),
          transitions: transitions
        }
      end)

    %{
      total_participants: total_participants,
      changed_participants: changed_participants,
      unchanged_participants: total_participants - changed_participants,
      changed_percent: percent(changed_participants, total_participants),
      statements: statement_stats,
      delegates:
        Enum.map(reconsideration.delegates, fn delegate ->
          count = Map.get(delegate_counts, delegate.author_id, 0)

          %{
            author_id: delegate.author_id,
            author: delegate.author,
            count: count,
            percent: percent(count, total_participants)
          }
        end)
    }
  end

  defp transition_sort_key(transition) do
    {-transition.count, answer_sort_order(transition.before_answer),
     answer_sort_order(transition.after_answer)}
  end

  defp answer_sort_order(:for), do: 0
  defp answer_sort_order(:abstain), do: 1
  defp answer_sort_order(:against), do: 2

  defp preload_experience(reconsideration) do
    statement_query =
      from rs in ReconsiderationStatement, order_by: rs.position, preload: [:statement]

    delegate_query = from d in Delegate, order_by: d.position, preload: [:author]

    Repo.preload(reconsideration,
      creator: [],
      reconsideration_statements: statement_query,
      delegates: delegate_query
    )
  end

  defp resolve_statement_refs(value) do
    resolve_refs(
      value,
      fn ref ->
        case ref_path(ref) do
          "/p/" <> slug ->
            Repo.get_by(Statement, slug: slug)

          id_or_slug ->
            maybe_get(Statement, normalize_id(id_or_slug)) ||
              Repo.get_by(Statement, slug: id_or_slug)
        end
      end,
      "statement"
    )
  end

  defp resolve_author_refs(value) do
    resolve_refs(
      value,
      fn ref ->
        case ref_path(ref) do
          "/x/" <> username -> Repo.get_by(Author, twitter_username: username)
          "/a/" <> id -> maybe_get(Author, normalize_id(id))
          "@" <> username -> Repo.get_by(Author, twitter_username: username)
          id -> maybe_get(Author, normalize_id(id))
        end
      end,
      "person"
    )
  end

  defp resolve_refs(value, resolver, label) do
    refs = split_refs(value)

    refs
    |> Enum.reduce_while({:ok, []}, fn ref, {:ok, records} ->
      case resolver.(ref) do
        nil -> {:halt, {:error, "Could not find #{label} “#{ref}”."}}
        record -> {:cont, {:ok, [record | records]}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, records |> Enum.reverse() |> Enum.uniq_by(& &1.id)}
      error -> error
    end
  end

  defp split_refs(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_refs(_), do: []

  defp ref_path(ref) do
    case URI.parse(ref) do
      %URI{scheme: scheme, path: path} when scheme in ["http", "https"] and is_binary(path) ->
        path

      _ ->
        ref
    end
  end

  defp records_in_order(_schema, []), do: []

  defp records_in_order(schema, ids) do
    records = schema |> where([record], record.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})
    Enum.map(ids, &Map.get(records, &1)) |> Enum.reject(&is_nil/1)
  end

  defp validate_statement_count(statements) when length(statements) in 1..3, do: :ok
  defp validate_statement_count(_), do: {:error, "Choose between one and three statements."}

  defp normalize_responses(responses) when is_map(responses) do
    responses
    |> Enum.reduce_while({:ok, []}, fn {statement_id, answers}, {:ok, acc} ->
      with id when is_integer(id) <- normalize_id(statement_id),
           {:ok, before_answer} <- normalize_answer(answers["before"] || answers[:before]),
           {:ok, after_answer} <- normalize_answer(answers["after"] || answers[:after]) do
        {:cont, {:ok, [{id, %{before: before_answer, after: after_answer}} | acc]}}
      else
        _ -> {:halt, {:error, :invalid_answers}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_responses(_), do: {:error, :invalid_answers}

  defp validate_response_statements(responses, statement_ids) do
    response_ids = responses |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    if response_ids == MapSet.new(statement_ids),
      do: :ok,
      else: {:error, :incomplete_answers}
  end

  defp normalize_delegate_ids(delegate_ids) when is_list(delegate_ids) do
    ids = delegate_ids |> Enum.map(&normalize_id/1)

    if Enum.all?(ids, &is_integer/1),
      do: {:ok, Enum.uniq(ids)},
      else: {:error, :invalid_delegates}
  end

  defp normalize_delegate_ids(nil), do: {:ok, []}
  defp normalize_delegate_ids(_), do: {:error, :invalid_delegates}

  defp validate_delegates(ids, allowed_ids) do
    if Enum.all?(ids, &(&1 in allowed_ids)),
      do: :ok,
      else: {:error, :invalid_delegates}
  end

  defp normalize_answer(answer) when answer in @answers, do: {:ok, answer}

  defp normalize_answer(answer) when is_binary(answer) do
    case answer do
      "for" -> {:ok, :for}
      "against" -> {:ok, :against}
      "abstain" -> {:ok, :abstain}
      _ -> {:error, :invalid_answer}
    end
  end

  defp normalize_answer(_), do: {:error, :invalid_answer}

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil

  defp maybe_get(_schema, nil), do: nil
  defp maybe_get(schema, id), do: Repo.get(schema, id)

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp unique_slug(title) do
    base = title |> to_string() |> Slug.slugify() |> String.slice(0, 70)
    base = if base == "", do: "reconsider", else: base
    find_unique_slug(base, 1)
  end

  defp find_unique_slug(base, 1) do
    if Repo.exists?(from r in Reconsideration, where: r.slug == ^base),
      do: find_unique_slug(base, 2),
      else: base
  end

  defp find_unique_slug(base, suffix) do
    candidate = "#{base}-#{suffix}"

    if Repo.exists?(from r in Reconsideration, where: r.slug == ^candidate),
      do: find_unique_slug(base, suffix + 1),
      else: candidate
  end

  defp percent(_part, 0), do: 0
  defp percent(part, total), do: round(part * 100 / total)
end
