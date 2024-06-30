defmodule YouCongress.VotesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Votes` context.
  """

  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.Votes.AnswersFixtures
  import YouCongress.OpinionsFixtures
  alias YouCongress.Opinions
  alias YouCongress.Votes

  @doc """
  Generate a vote.
  """
  def vote_fixture(attrs \\ %{}, generate_opinion \\ false) do
    generate_opinion = if generate_opinion, do: true, else: nil
    voting_id = voting_fixture().id

    attrs =
      attrs
      |> Enum.into(%{
        author_id: author_fixture().id,
        voting_id: voting_id,
        answer_id: answer_fixture().id
      })

    #  This should be fixed
    #  A vote has an opinion_id and an opinion has a vote_id
    #  This is because, at the moment, all root opinions belong to a vote
    #  and a vote displays a single opinion per user in a given voting
    {attrs, opinion} = add_opinion_if_not_present(attrs, voting_id, generate_opinion)
    {:ok, vote} = Votes.create_vote(attrs)
    if opinion, do: Opinions.update_opinion(opinion, %{vote_id: vote.id})

    vote
  end

  defp add_opinion_if_not_present(attrs, voting_id, generate_opinion) do
    if !generate_opinion || attrs[:opinion_id] do
      {attrs, nil}
    else
      opinion = opinion_fixture(%{voting_id: voting_id}, false)
      attrs = attrs |> Map.put(:opinion_id, opinion.id)
      {attrs, opinion}
    end
  end
end
