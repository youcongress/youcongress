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
  alias YouCongress.OpinionStatementVerifications.OpinionStatementVerification

  schema "opinions_statements" do
    field :verification_status, Ecto.Enum,
      values: [:verified, :ai_verified, :ai_unverifiable, :endorsed, :disputed, :unverifiable]

    belongs_to :opinion, Opinion
    belongs_to :statement, Statement
    belongs_to :user, User
    has_many :verifications, OpinionStatementVerification

    timestamps()
  end

  @doc false
  def changeset(opinion_statement, attrs) do
    opinion_statement
    |> cast(attrs, [:opinion_id, :statement_id, :user_id, :verification_status])
    |> validate_required([:opinion_id, :statement_id, :user_id])
    |> unique_constraint([:opinion_id, :statement_id])
    |> foreign_key_constraint(:opinion_id)
    |> foreign_key_constraint(:statement_id)
    |> foreign_key_constraint(:user_id)
  end
end
