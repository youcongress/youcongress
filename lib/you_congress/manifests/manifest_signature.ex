defmodule YouCongress.Manifests.ManifestSignature do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manifest_signatures" do
    belongs_to :manifest, YouCongress.Manifests.Manifest
    belongs_to :user, YouCongress.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(signature, attrs) do
    signature
    |> cast(attrs, [:manifest_id, :user_id])
    |> validate_required([:manifest_id, :user_id])
    |> unique_constraint([:manifest_id, :user_id])
  end
end
