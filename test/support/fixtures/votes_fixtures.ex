defmodule YouCongress.VotesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Votes` context.
  """

  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.Votes.AnswersFixtures
  import YouCongress.OpinionsFixtures

  @doc """
  Generate a vote.
  """
  def vote_fixture(attrs \\ %{}) do
    {:ok, vote} =
      attrs
      |> Enum.into(%{
        author_id: author_fixture().id,
        voting_id: voting_fixture().id,
        answer_id: answer_fixture().id
      })
      |> add_opinion_id_if_missing()
      |> YouCongress.Votes.create_vote()

    vote
  end

  def add_opinion_id_if_missing(attrs) do
    if Map.has_key?(attrs, :opinion_id) do
      attrs
    else
      opinion =
        opinion_fixture(%{
          author_id: attrs.author_id,
          voting_id: attrs.voting_id,
          content: Faker.Lorem.sentence()
        })

      attrs |> Map.put(:opinion_id, opinion.id)
    end
  end
end
