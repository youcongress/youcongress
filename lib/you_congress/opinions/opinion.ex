defmodule YouCongress.Opinions.Opinion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "opinions" do
    field :source_url, :string
    field :content, :string
    field :twin, :boolean, default: false
    field :author_id, :id
    field :user_id, :id
    field :vote_id, :id

    timestamps()
  end

  @doc false
  def changeset(opinion, attrs) do
    opinion
    |> cast(attrs, [:content, :source_url, :twin, :vote_id, :author_id, :user_id])
    |> validate_required([:content, :twin])
  end
end
