defmodule YouCongress.Reconsiderations.DelegateSelection do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Reconsiderations.Reconsideration

  schema "reconsideration_delegate_selections" do
    belongs_to :reconsideration, Reconsideration
    belongs_to :participant_author, Author
    belongs_to :delegate_author, Author

    timestamps(updated_at: false)
  end

  def changeset(selection, attrs) do
    selection
    |> cast(attrs, [:reconsideration_id, :participant_author_id, :delegate_author_id])
    |> validate_required([:reconsideration_id, :participant_author_id, :delegate_author_id])
    |> unique_constraint(
      [:reconsideration_id, :participant_author_id, :delegate_author_id],
      name: :reconsideration_delegate_selections_unique_index
    )
  end
end
