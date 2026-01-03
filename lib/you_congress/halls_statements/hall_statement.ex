defmodule YouCongress.HallsStatements.HallStatement do
  @moduledoc """
  HallStatement schema - join table between Halls and Statements.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Statements.Statement
  alias YouCongress.Halls.Hall

  schema "halls_statements" do
    belongs_to(:statement, Statement)
    belongs_to(:hall, Hall)
  end

  @doc false
  def changeset(hall_statement, attrs) do
    hall_statement
    |> cast(attrs, [:statement_id, :hall_id])
    |> validate_required([:statement_id, :hall_id])
  end
end
