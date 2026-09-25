defmodule YouCongress.Reconsiderations.Reconsideration do
  @moduledoc """
  An article or video that asks participants to report their position before and after.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author

  alias YouCongress.Reconsiderations.{
    Delegate,
    DelegateSelection,
    ReconsiderationStatement,
    Response
  }

  schema "reconsiderations" do
    field :title, :string
    field :slug, :string
    field :description, :string
    field :content_url, :string
    field :content_type, Ecto.Enum, values: [:article, :video]
    field :published, :boolean, default: true

    belongs_to :creator, Author
    has_many :reconsideration_statements, ReconsiderationStatement
    has_many :delegates, Delegate
    has_many :delegate_selections, DelegateSelection
    has_many :responses, Response

    timestamps()
  end

  def changeset(reconsideration, attrs) do
    reconsideration
    |> cast(attrs, [
      :title,
      :slug,
      :description,
      :content_url,
      :content_type,
      :creator_id,
      :published
    ])
    |> validate_required([:title, :slug, :content_url, :content_type, :creator_id])
    |> validate_length(:title, max: 180)
    |> validate_length(:description, max: 1_000)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_content_url()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:creator_id)
  end

  defp validate_content_url(changeset) do
    validate_change(changeset, :content_url, fn :content_url, value ->
      case URI.new(value) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [content_url: "must be a valid HTTP or HTTPS URL"]
      end
    end)
  end
end
