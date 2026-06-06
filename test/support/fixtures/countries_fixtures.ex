defmodule YouCongress.CountriesFixtures do
  @moduledoc """
  This module defines test helpers for creating countries.
  """

  def country_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        name: "Country #{unique}",
        phone_prefix: "+#{unique}"
      })

    {:ok, country} = YouCongress.Countries.create_country(attrs)

    country
  end
end
