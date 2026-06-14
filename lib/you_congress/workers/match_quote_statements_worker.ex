defmodule YouCongress.Workers.MatchQuoteStatementsWorker do
  @moduledoc """
  Uses AI to discover statements related to a sourced quote and link them.

  Args:
  - opinion_id: the sourced quote id.
  """

  use Oban.Worker,
    queue: :verification,
    max_attempts: 1,
    unique: [states: [:scheduled, :available], keys: [:opinion_id]]

  require Logger

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements
  alias YouCongress.Statements
  alias YouCongress.Verifications.QuoteStatementMatcher
  alias YouCongress.Votes

  @answers ~w(for against abstain)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"opinion_id" => opinion_id}}) do
    with user_id when not is_nil(user_id) <- system_user_id(),
         %Opinion{} = opinion <- load_quote(opinion_id),
         statements <- candidate_statements(opinion),
         {:ok, matches} <- QuoteStatementMatcher.match_statements(opinion, statements) do
      Logger.info(
        "MatchQuoteStatementsWorker found #{length(matches)} for opinion_id #{opinion_id}"
      )

      persist_matches(opinion, statements, matches, user_id)
      :ok
    else
      nil ->
        Logger.info(
          "MatchQuoteStatementsWorker did not find any statements for quote #{inspect(opinion_id)}"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "MatchQuoteStatementsWorker Failed to match statements for quote ##{inspect(opinion_id)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp load_quote(opinion_id) do
    case Opinions.get_opinion(normalize_id(opinion_id)) do
      %Opinion{source_url: nil} -> nil
      %Opinion{author_id: nil} -> nil
      %Opinion{} = opinion -> opinion
      nil -> nil
    end
  end

  defp candidate_statements(%Opinion{id: opinion_id}) do
    statements = Statements.list_statements(order: :id_asc)
    statement_ids = Enum.map(statements, & &1.id)

    linked_statement_ids =
      opinion_id
      |> OpinionsStatements.get_opinion_statements_by_statement_ids(statement_ids)
      |> Map.keys()
      |> MapSet.new()

    Enum.reject(statements, &MapSet.member?(linked_statement_ids, &1.id))
  end

  defp persist_matches(%Opinion{} = opinion, statements, matches, user_id)
       when is_list(matches) do
    statements_by_id = Map.new(statements, &{&1.id, &1})

    matches
    |> Enum.map(&normalize_match/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn {statement_id, _answer} -> statement_id end)
    |> Enum.each(fn {statement_id, answer} ->
      case Map.fetch(statements_by_id, statement_id) do
        {:ok, statement} -> persist_match(opinion, statement, answer, user_id)
        :error -> :ok
      end
    end)
  end

  defp persist_matches(_opinion, _statements, _matches, _user_id), do: :ok

  defp persist_match(%Opinion{} = opinion, statement, answer, user_id) do
    with :ok <- link_opinion_statement(opinion, statement, user_id),
         {:ok, _vote} <- create_or_update_vote(opinion, statement, answer) do
      :ok
    else
      {:error, reason} ->
        Logger.error(
          "Failed to persist statement match for quote #{opinion.id} and statement #{statement.id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp link_opinion_statement(%Opinion{} = opinion, statement, user_id) do
    case Opinions.add_opinion_to_statement(opinion, statement, user_id) do
      {:ok, _opinion} -> :ok
      {:error, :already_associated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_or_update_vote(%Opinion{author_id: author_id} = opinion, statement, answer) do
    attrs = %{
      statement_id: statement.id,
      author_id: author_id,
      answer: answer,
      opinion_id: opinion.id,
      direct: true,
      twin: false
    }

    case Votes.get_by(statement_id: statement.id, author_id: author_id) do
      nil -> Votes.create_vote(attrs)
      vote -> Votes.update_vote(vote, attrs)
    end
  end

  defp normalize_match(match) when is_map(match) do
    statement_id = normalize_id(match["statement_id"] || match[:statement_id])
    answer = normalize_answer(match["answer"] || match[:answer])

    if statement_id && answer, do: {statement_id, answer}, else: nil
  end

  defp normalize_match(_), do: nil

  defp normalize_answer(answer) when is_binary(answer) do
    downcased = String.downcase(answer)
    if downcased in @answers, do: String.to_existing_atom(downcased), else: nil
  end

  defp normalize_answer(answer) when answer in [:for, :against, :abstain], do: answer
  defp normalize_answer(_), do: nil

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil

  defp system_user_id do
    case Application.get_env(:you_congress, :verification_user_id) do
      nil -> nil
      "" -> nil
      id when is_integer(id) -> id
      id when is_binary(id) -> normalize_id(id)
    end
  end
end
