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
  def sync!(statement_id, classification \\ nil) do
    statement = Statements.get_statement!(statement_id, preload: [:halls])
    classification = classification || Halls.classify!(statement.title)
    %{main_tag: main_tag, other_tags: other_tags} = classification
    all_tags = [main_tag | other_tags]
    {:ok, halls} = Halls.list_or_create_by_names(all_tags)

    link(statement, halls, main_tag)
  end

  @spec link(Statement.t(), [Hall.t()], binary) ::
          {:ok, Statement.t()} | {:error, Ecto.Changeset.t()}
  defp link(statement, halls, main_tag) do
    # Delete existing associations first
    delete_halls_statements(statement)

    # Insert new associations with is_main flag
    Enum.each(halls, fn hall ->
      %HallStatement{}
      |> HallStatement.changeset(%{
        statement_id: statement.id,
        hall_id: hall.id,
        is_main: hall.name == main_tag
      })
      |> Repo.insert!()
    end)

    {:ok, Statements.get_statement!(statement.id, preload: [:halls])}
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

  def get_random_statements_from_hall(hall_name, limit, exclude_ids \\ []) do
    from(v in Statement,
      join: hs in HallStatement,
      on: hs.statement_id == v.id,
      join: h in Hall,
      on: hs.hall_id == h.id,
      where: h.name == ^hall_name and hs.is_main == true and v.id not in ^exclude_ids,
      order_by: fragment("RANDOM()"),
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_main_hall(statement_id) do
    hall_id =
      from(hs in HallStatement, where: hs.statement_id == ^statement_id and hs.is_main == true)
      |> select([hs], hs.hall_id)
      |> Repo.one()

    if(hall_id) do
      Halls.get_hall!(hall_id)
    end
  end
end
