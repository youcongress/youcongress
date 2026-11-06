defmodule YouCongress.Councils.Member do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "council_members" do
    field :list_id, :id
    field :author_id, :id
    field :reason, :string
    field :source_url, :string
    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:list_id, :author_id, :reason, :source_url])
    |> validate_required([:list_id, :author_id])
  end
end
