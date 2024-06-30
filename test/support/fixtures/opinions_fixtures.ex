defmodule YouCongress.OpinionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Opinions` context.
  """

  alias YouCongress.{VotingsFixtures, AccountsFixtures, VotesFixtures, AuthorsFixtures}

  @doc """
  Generate an opinion.
  """
  def opinion_fixture(attrs \\ %{}, generate_vote \\ false) do
    generate_vote = if !generate_vote, do: nil, else: true
    voting_id = attrs[:voting_id] || VotingsFixtures.voting_fixture().id
    author_id = attrs[:author_id] || AuthorsFixtures.author_fixture().id
    user_id = attrs[:user_id] || AccountsFixtures.user_fixture(%{author_id: author_id}).id

    {:ok, opinion} =
      attrs
      |> Enum.into(%{
        content: "some content",
        source_url: Faker.Internet.url(),
        twin: true,
        voting_id: voting_id,
        user_id: user_id,
        author_id: author_id,
        vote_id:
          generate_vote &&
            VotesFixtures.vote_fixture(
              %{
                voting_id: voting_id,
                user_id: user_id,
                author_id: author_id
              },
              false
            ).id
      })
      |> YouCongress.Opinions.create_opinion()

    opinion
  end
end
