defmodule YouCongress.VotingsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Votings` context.
  """

  @doc """
  Generate a voting.
  """
  def voting_fixture(attrs \\ %{}) do
    {:ok, voting} =
      attrs
      |> Enum.into(%{
        title: Faker.Lorem.sentence()
      })
      |> YouCongress.Votings.create_voting()

    voting
  end
end
