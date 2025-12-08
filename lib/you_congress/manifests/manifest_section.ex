defmodule YouCongress.Manifests.ManifestSection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manifest_sections" do
    field :body, :string
    field :weight, :integer, default: 0

    belongs_to :manifest, YouCongress.Manifests.Manifest
    belongs_to :voting, YouCongress.Votings.Voting

    timestamps()
  end

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:body, :manifest_id, :voting_id, :weight])
    |> validate_required([:body, :manifest_id])
    |> validate_length(:body, min: 1)
  end
end
