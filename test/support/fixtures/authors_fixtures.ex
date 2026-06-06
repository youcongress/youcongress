defmodule YouCongress.AuthorsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Authors` context.
  """

  @doc """
  Generate a author.
  """
  def author_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> put_default_country()

    {:ok, author} =
      attrs
      |> Enum.into(%{
        bio: Faker.Lorem.sentence(),
        twin_origin: true,
        public_figure: true,
        name: Faker.Person.name() |> String.replace("'", ""),
        twitter_username: Faker.Internet.user_name(),
        wikipedia_url:
          "https://en.wikipedia.org/wiki/" <>
            String.replace(Faker.Internet.user_name(), ~r/[^a-zA-Z0-9_]/, "_")
      })
      |> YouCongress.Authors.create_author()

    author
  end

  defp put_default_country(attrs) do
    if Map.has_key?(attrs, :country_id) or Map.has_key?(attrs, "country_id") or
         Map.has_key?(attrs, :country) or Map.has_key?(attrs, "country") do
      attrs
    else
      Map.put(attrs, :country_id, YouCongress.CountriesFixtures.country_fixture().id)
    end
  end
end
