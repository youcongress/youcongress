defmodule YouCongress.VotesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Votes` context.
  """

  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.Votes.AnswersFixtures

  @doc """
  Generate a vote.
  """
  def vote_fixture(attrs \\ %{}) do
    {:ok, vote} =
      attrs
      |> Enum.into(%{
        opinion: Faker.Lorem.sentence(),
        author_id: author_fixture().id,
        voting_id: voting_fixture().id,
        answer_id: answer_fixture().id
      })
      |> YouCongress.Votes.create_vote()

    vote
  end
end
