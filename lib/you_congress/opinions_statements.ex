defmodule YouCongress.OpinionsStatements do
  @moduledoc """
  The OpinionsStatements context for managing the many-to-many relationship between opinions and statements.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Endorsements
  alias YouCongress.FeatureFlags
  alias YouCongress.Repo
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.VerificationStatus
  alias YouCongress.Workers.VerificationWorker

  @doc """
  Returns a map of {statement_id, opinion} pairs for the given statement_ids and current_user's author_id.

  ## Examples

      iex> get_opinions_by_statement_ids([1, 2, 3], current_user)
      %{1 => %Opinion{}, 2 => %Opinion{}}

  """
  def get_opinions_by_statement_ids(statement_ids, current_user)
      when is_list(statement_ids) and not is_nil(current_user) do
    from(ov in "opinions_statements",
      join: o in Opinion,
      on: ov.opinion_id == o.id,
      where: ov.statement_id in ^statement_ids and o.author_id == ^current_user.author_id,
      select: {ov.statement_id, o}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_opinions_by_statement_ids(_, nil), do: %{}
  def get_opinions_by_statement_ids([], _), do: %{}

  @doc """
  Fetches the join row linking an opinion to a statement, or nil.
  """
  def get_opinion_statement(opinion_id, statement_id) do
    Repo.get_by(OpinionStatement, opinion_id: opinion_id, statement_id: statement_id)
  end

  @doc """
  Returns a map of `{statement_id => %OpinionStatement{}}` for one opinion across
  the given statement_ids.
  """
  def get_opinion_statements_by_statement_ids(opinion_id, statement_ids)
      when is_list(statement_ids) do
    from(os in OpinionStatement,
      where: os.opinion_id == ^opinion_id and os.statement_id in ^statement_ids
    )
    |> Repo.all()
    |> Map.new(fn os -> {os.statement_id, os} end)
  end

  @doc """
  Creates an opinion statement.

  ## Examples

      iex> create_opinion_statement(%{opinion_id: 1, statement_id: 1, user_id: 1})
      {:ok, %OpinionStatement{}}

      iex> create_opinion_statement(%{opinion_id: 1, statement_id: 1, user_id: 1})
      {:error, %Ecto.Changeset{}}
  """
  def create_opinion_statement(params) do
    result =
      %OpinionStatement{}
      |> OpinionStatement.changeset(params)
      |> Repo.insert()

    with {:ok, opinion_statement} <- result do
      sync_opinions_count(opinion_statement.statement_id)
      Endorsements.endorse_opinion_statement(opinion_statement, opinion_statement.user_id)
      maybe_enqueue_relevance_verification(opinion_statement)
      {:ok, opinion_statement}
    end
  end

  defp sync_opinions_count(statement_id) do
    %{"statement_id" => statement_id}
    |> YouCongress.Workers.SyncStatementOpinionsCountWorker.new()
    |> Oban.insert()
  end

  defp maybe_enqueue_relevance_verification(%OpinionStatement{id: id, opinion_id: opinion_id}) do
    if FeatureFlags.enabled?(:automatic_verifications) &&
         relevance_verification_ready?(opinion_id) do
      %{"subject" => "relevance", "id" => id}
      |> VerificationWorker.new()
      |> Oban.insert()
    end
  end

  defp relevance_verification_ready?(opinion_id) do
    from(o in Opinion, where: o.id == ^opinion_id, select: o.verification_status)
    |> Repo.one()
    |> VerificationStatus.positive?()
  end
end
