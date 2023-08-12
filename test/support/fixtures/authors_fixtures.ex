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
        bio: "some bio",
        country: "some country",
        is_twin: true,
        name: "some name",
        twitter_url: "some twitter_url",
        wikipedia_url: "some wikipedia_url"
      })
      |> YouCongress.Authors.create_author()

    author
  end
end
