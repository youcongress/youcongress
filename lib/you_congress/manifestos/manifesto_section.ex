defmodule YouCongress.Manifestos.ManifestoSection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manifesto_sections" do
    field :body, :string
    field :weight, :integer, default: 0

    belongs_to :manifesto, YouCongress.Manifestos.Manifesto
    belongs_to :voting, YouCongress.Votings.Voting

    timestamps()
  end

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:body, :manifesto_id, :voting_id, :weight])
    |> validate_required([:body, :manifesto_id])
    |> validate_length(:body, min: 1)
  end
end
