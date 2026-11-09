defmodule YouCongress.TrustNetwork.Request do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "trust_requests" do
    field :user_id, :id
    field :author_id, :id
    field :statement_id, :id
    field :kind, :string
    field :body, :string
    field :source_url, :string
    field :status, :string, default: "open"
    field :resolution, :string
    field :attempts, {:array, :map}, default: []
    timestamps()
  end

  def changeset(record, attrs),
    do:
      record
      |> cast(attrs, [
        :user_id,
        :author_id,
        :statement_id,
        :kind,
        :body,
        :source_url,
        :status,
        :resolution,
        :attempts
      ])
      |> validate_required([:kind, :body, :status])
end
