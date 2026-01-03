defmodule YouCongress.OpinionsStatements.OpinionStatement do
  @moduledoc """
  Join schema for the many-to-many relationship between opinions and statements.
  Includes user_id to track who associated the opinion with the statement.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements.Statement
  alias YouCongress.Accounts.User

  schema "opinions_statements" do
    belongs_to :opinion, Opinion
    belongs_to :statement, Statement
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(opinion_statement, attrs) do
    opinion_statement
    |> cast(attrs, [:opinion_id, :statement_id, :user_id])
    |> validate_required([:opinion_id, :statement_id, :user_id])
    |> unique_constraint([:opinion_id, :statement_id])
    |> foreign_key_constraint(:opinion_id)
    |> foreign_key_constraint(:statement_id)
    |> foreign_key_constraint(:user_id)
  end
end
