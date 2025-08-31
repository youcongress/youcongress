defmodule YouCongress.OpinionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Opinions` context.
  """

  alias YouCongress.{AccountsFixtures, AuthorsFixtures}

  @doc """
  Generate an opinion.
  """
  def opinion_fixture(attrs \\ %{}) do
    author_id = attrs[:author_id] || AuthorsFixtures.author_fixture().id
    user_id = attrs[:user_id] || AccountsFixtures.user_fixture(%{author_id: author_id}).id

    {:ok, %{opinion: opinion}} =
      attrs
      |> Enum.into(%{
        content: "some content",
        source_url: Faker.Internet.url(),
        twin: true,
        user_id: user_id,
        author_id: author_id
      })
      |> YouCongress.Opinions.create_opinion()

    # Reload from database to match what list_opinions() returns (no preloaded associations)
    YouCongress.Opinions.get_opinion!(opinion.id)
  end
end
