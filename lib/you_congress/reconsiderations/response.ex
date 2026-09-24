defmodule YouCongress.Reconsiderations.Response do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Reconsiderations.Reconsideration
  alias YouCongress.Statements.Statement

  schema "reconsideration_responses" do
    field :before_answer, Ecto.Enum, values: [:for, :against, :abstain]
    field :after_answer, Ecto.Enum, values: [:for, :against, :abstain]

    belongs_to :reconsideration, Reconsideration
    belongs_to :statement, Statement
    belongs_to :author, Author

    timestamps()
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [
      :reconsideration_id,
      :statement_id,
      :author_id,
      :before_answer,
      :after_answer
    ])
    |> validate_required([
      :reconsideration_id,
      :statement_id,
      :author_id,
      :before_answer,
      :after_answer
    ])
    |> unique_constraint([:reconsideration_id, :statement_id, :author_id],
      name: :reconsideration_responses_campaign_statement_author_index
    )
  end
end
