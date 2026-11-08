defmodule YouCongress.Councils.Council do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "councils" do
    field :author_id, :id
    field :invited_by_id, :id
    field :version, :integer, default: 1
    field :onboarding_completed, :boolean, default: false
    field :published, :boolean, default: false
    field :digest, :string, default: "off"
    has_many :lists, YouCongress.Councils.List, preload_order: [asc: :position]
    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:author_id, :version, :published, :digest])
    |> validate_required([:author_id, :version])
  end
end
