defmodule YouCongress.Reconsiderations.ReconsiderationStatement do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Reconsiderations.Reconsideration
  alias YouCongress.Statements.Statement

  schema "reconsideration_statements" do
    field :statement_title, :string
    field :position, :integer

    belongs_to :reconsideration, Reconsideration
    belongs_to :statement, Statement

    timestamps(updated_at: false)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:reconsideration_id, :statement_id, :statement_title, :position])
    |> validate_required([:reconsideration_id, :statement_id, :statement_title, :position])
    |> unique_constraint([:reconsideration_id, :statement_id],
      name: :reconsideration_statements_campaign_statement_index
    )
    |> unique_constraint([:reconsideration_id, :position])
  end
end
