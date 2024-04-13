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
    |> validate_source_url_if_present()
  end

  defp validate_source_url_if_present(changeset) do
    case get_field(changeset, :source_url) do
      nil ->
        changeset

      source_url ->
        if starts_with_http(source_url) do
          changeset
        else
          add_error(changeset, :source_url, "is not a valid URL")
        end
    end
  end

  defp starts_with_http("http" <> _), do: true
  defp starts_with_http(_), do: false
end
