defmodule YouCongress.Reconsiderations.Delegate do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Reconsiderations.Reconsideration

  schema "reconsideration_delegates" do
    field :position, :integer

    belongs_to :reconsideration, Reconsideration
    belongs_to :author, Author

    timestamps(updated_at: false)
  end

  def changeset(delegate, attrs) do
    delegate
    |> cast(attrs, [:reconsideration_id, :author_id, :position])
    |> validate_required([:reconsideration_id, :author_id, :position])
    |> unique_constraint([:reconsideration_id, :author_id])
    |> unique_constraint([:reconsideration_id, :position])
  end
end
