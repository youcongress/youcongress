defmodule YouCongress.HallsStatements do
  @moduledoc """
  Relationships between Halls and Statements.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Halls
  alias YouCongress.Halls.Hall
  alias YouCongress.HallsStatements.HallStatement

  def sync! do
    Enum.each(Statements.list_statements(), fn statement -> sync!(statement.id) end)
  end

  @doc """
  Updates the halls associated with a statement.

  ## Raises
    - Raises an error if the statement does not exist or if there's an issue updating the statement's halls.
  """
  def sync!(statement_id, tags \\ nil) do
    statement = Statements.get_statement!(statement_id, preload: [:halls])
    tags = tags || Halls.classify!(statement.title)
    {:ok, halls} = Halls.list_or_create_by_names(tags)

    link(statement, halls)
  end

  @spec link(Statement.t(), [Hall.t()]) :: {:ok, Statement.t()} | {:error, Ecto.Changeset.t()}
  defp link(statement, halls) do
    statement_changeset =
      statement
      |> Statement.changeset(%{})
      |> Ecto.Changeset.put_assoc(:halls, halls)

    Repo.update(statement_changeset)
  end

  def delete_halls_statements(%Statement{id: statement_id}) do
    from(hv in HallStatement, where: hv.statement_id == ^statement_id)
    |> Repo.delete_all()
  end

  def get_random_statement(hall_name) do
    from(v in Statement,
      join: h in assoc(v, :halls),
      where: h.name == ^hall_name,
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
  end

  def get_random_statements(hall_name, limit, exclude_ids \\ []) do
    from(v in Statement,
      join: h in assoc(v, :halls),
      where: h.name == ^hall_name and v.id not in ^exclude_ids,
      order_by: fragment("RANDOM()"),
      limit: ^limit
    )
    |> Repo.all()
  end
end
