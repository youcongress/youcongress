defmodule YouCongress.OpinionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Opinions` context.
  """

  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.Opinions.AnswersFixtures

  @doc """
  Generate a opinion.
  """
  def opinion_fixture(attrs \\ %{}) do
    {:ok, opinion} =
      attrs
      |> Enum.into(%{
        opinion: Faker.Lorem.sentence(),
        author_id: author_fixture().id,
        voting_id: voting_fixture().id,
        answer_id: answer_fixture().id
      })
      |> YouCongress.Opinions.create_opinion()

    opinion
  end
end
