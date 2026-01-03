defmodule YouCongress.OpinionsStatements do
  @moduledoc """
  The OpinionsStatements context for managing the many-to-many relationship between opinions and statements.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement

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
  Creates an opinion statement.

  ## Examples

      iex> create_opinion_statement(%{opinion_id: 1, statement_id: 1, user_id: 1})
      {:ok, %OpinionStatement{}}

      iex> create_opinion_statement(%{opinion_id: 1, statement_id: 1, user_id: 1})
      {:error, %Ecto.Changeset{}}
  """
  def create_opinion_statement(params) do
    %OpinionStatement{}
    |> OpinionStatement.changeset(params)
    |> Repo.insert()
  end
end
