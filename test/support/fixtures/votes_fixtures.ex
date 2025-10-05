defmodule YouCongress.VotesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Votes` context.
  """

  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.Votes.AnswersFixtures
  import YouCongress.OpinionsFixtures
  alias YouCongress.Votes

  @doc """
  Generate a vote.
  """
  def vote_fixture(attrs \\ %{}, generate_opinion \\ false) do
    generate_opinion = if generate_opinion, do: true, else: nil
    voting_id = attrs[:voting_id] || voting_fixture().id

    attrs =
      attrs
      |> Enum.into(%{
        author_id: author_fixture().id,
        voting_id: voting_id,
        answer_id: answer_fixture().id
      })

    {attrs, _opinion} = add_opinion_if_not_present(attrs, voting_id, generate_opinion)
    {:ok, vote} = Votes.create_vote(attrs)

    vote
  end

  defp add_opinion_if_not_present(attrs, voting_id, generate_opinion) do
    if !generate_opinion || attrs[:opinion_id] do
      {attrs, nil}
    else
      opinion = opinion_fixture(%{voting_id: voting_id, author_id: attrs[:author_id], twin: !!attrs[:twin]})
      attrs = attrs |> Map.put(:opinion_id, opinion.id)
      {attrs, opinion}
    end
  end
end
