defmodule YouCongress.Manifestos.ManifestoSignature do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manifesto_signatures" do
    belongs_to :manifesto, YouCongress.Manifestos.Manifesto
    belongs_to :user, YouCongress.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(signature, attrs) do
    signature
    |> cast(attrs, [:manifesto_id, :user_id])
    |> validate_required([:manifesto_id, :user_id])
    |> unique_constraint([:manifesto_id, :user_id])
  end
end
