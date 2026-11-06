defmodule YouCongress.TrustNetwork.Recommendation do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "trust_recommendations" do
    field :author_id, :id
    field :nominee_id, :id
    field :scope, :string
    field :reason, :string
    field :source_url, :string
    field :published, :boolean, default: false
    timestamps()
  end

  def changeset(record, attrs),
    do:
      record
      |> cast(attrs, [:author_id, :nominee_id, :scope, :reason, :source_url, :published])
      |> validate_required([:author_id, :nominee_id, :scope])
end
