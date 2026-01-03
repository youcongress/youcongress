defmodule YouCongress.VotesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Votes` context.
  """

  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures

  import YouCongress.OpinionsFixtures
  alias YouCongress.Votes

  @doc """
  Generate a vote.
  """
  def vote_fixture(attrs \\ %{}, generate_opinion \\ false) do
    generate_opinion = if generate_opinion, do: true, else: nil
    statement_id = attrs[:statement_id] || statement_fixture().id

    attrs =
      attrs
      |> Enum.into(%{
        author_id: author_fixture().id,
        statement_id: statement_id,
        answer: :for
      })

    {attrs, _opinion} = add_opinion_if_not_present(attrs, statement_id, generate_opinion)
    {:ok, vote} = Votes.create_vote(attrs)

    vote
  end

  defp add_opinion_if_not_present(attrs, statement_id, generate_opinion) do
    if !generate_opinion || attrs[:opinion_id] do
      {attrs, nil}
    else
      opinion =
        opinion_fixture(%{
          statement_id: statement_id,
          author_id: attrs[:author_id],
          twin: !!attrs[:twin]
        })

      attrs = attrs |> Map.put(:opinion_id, opinion.id)
      {attrs, opinion}
    end
  end
end
