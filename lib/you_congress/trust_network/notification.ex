defmodule YouCongress.TrustNetwork.Notification do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "trust_notifications" do
    field :author_id, :id
    field :key, :string
    field :body, :string
    field :path, :string
    field :read_at, :naive_datetime
    field :emailed_at, :naive_datetime
    timestamps()
  end

  def changeset(record, attrs),
    do:
      record
      |> cast(attrs, [:author_id, :key, :body, :path, :read_at, :emailed_at])
      |> validate_required([:author_id, :key, :body, :path])
end
