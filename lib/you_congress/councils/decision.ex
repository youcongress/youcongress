defmodule YouCongress.Councils.Decision do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "council_decisions" do
    field :author_id, :id
    field :statement_id, :id
    field :answer, :string
    field :council_version, :integer
    field :explanation, :map, default: %{}
    timestamps()
  end

  def current do
    import Ecto.Query

    from d in __MODULE__,
      join: c in YouCongress.Councils.Council,
      on: c.author_id == d.author_id and c.version == d.council_version,
      select: d
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:author_id, :statement_id, :answer, :council_version, :explanation])
    |> validate_required([:author_id, :statement_id, :council_version])
  end
end
