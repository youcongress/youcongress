defmodule YouCongress.Manifestos.Manifesto do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manifestos" do
    field :title, :string
    field :slug, :string
    field :active, :boolean, default: false

    belongs_to :user, YouCongress.Accounts.User
    has_many :sections, YouCongress.Manifestos.ManifestoSection
    has_many :signatures, YouCongress.Manifestos.ManifestoSignature

    timestamps()
  end

  @doc false
  def changeset(manifesto, attrs) do
    manifesto
    |> cast(attrs, [:title, :slug, :active, :user_id])
    |> validate_required([:title, :slug, :user_id])
    |> validate_length(:title, min: 3, max: 255)
    |> validate_length(:slug, min: 3, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must contain only lowercase letters, numbers, and hyphens")
    |> unique_constraint(:slug)
  end
end
