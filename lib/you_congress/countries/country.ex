defmodule YouCongress.Countries.Country do
  @moduledoc """
  Defines countries used for structured author locations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "countries" do
    field :name, :string
    field :iso_alpha2, :string
    field :iso_alpha3, :string
    field :phone_prefix, :string

    has_many :authors, YouCongress.Authors.Author

    timestamps()
  end

  @doc false
  def changeset(country, attrs) do
    country
    |> cast(attrs, [:name, :iso_alpha2, :iso_alpha3, :phone_prefix])
    |> normalize_codes()
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> unique_constraint(:iso_alpha2)
    |> unique_constraint(:iso_alpha3)
  end

  defp normalize_codes(changeset) do
    changeset
    |> update_change(:name, &blank_to_nil/1)
    |> update_change(:iso_alpha2, &normalize_iso/1)
    |> update_change(:iso_alpha3, &normalize_iso/1)
    |> update_change(:phone_prefix, &blank_to_nil/1)
  end

  defp normalize_iso(value) do
    value
    |> blank_to_nil()
    |> case do
      nil -> nil
      value -> String.upcase(value)
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp blank_to_nil(value), do: value
end
