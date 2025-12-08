defmodule YouCongress.Manifests.Manifest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manifests" do
    field :title, :string
    field :slug, :string
    field :active, :boolean, default: false

    belongs_to :user, YouCongress.Accounts.User
    has_many :sections, YouCongress.Manifests.ManifestSection
    has_many :signatures, YouCongress.Manifests.ManifestSignature

    timestamps()
  end

  @doc false
  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [:title, :slug, :active, :user_id])
    |> validate_required([:title, :slug, :user_id])
    |> validate_length(:title, min: 3, max: 255)
    |> validate_length(:slug, min: 3, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must contain only lowercase letters, numbers, and hyphens")
    |> unique_constraint(:slug)
  end
end
