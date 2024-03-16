defmodule YouCongress.AuthorsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Authors` context.
  """

  @doc """
  Generate a author.
  """
  def author_fixture(attrs \\ %{}) do
    {:ok, author} =
      attrs
      |> Enum.into(%{
        bio: Faker.Lorem.sentence(),
        country: Faker.Address.country(),
        twin_origin: true,
        name: Faker.Person.name(),
        twitter_username: Faker.Internet.user_name(),
        wikipedia_url: "https://wikipedia.org/wiki/" <> Faker.Internet.user_name()
      })
      |> YouCongress.Authors.create_author()

    author
  end
end
