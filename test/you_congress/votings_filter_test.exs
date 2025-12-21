defmodule YouCongress.VotingsFilterTest do
  use YouCongress.DataCase

  alias YouCongress.Votings
  alias YouCongress.Opinions

  import YouCongress.VotingsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures

  describe "list_votings_with_opinions_by_authors/1 returns multiple opinions" do
    test "returns multiple opinions per author if they exist (current behavior)" do
      author = author_fixture()
      voting = voting_fixture()

      # Create 2 opinions for the same author
      opinion1 = opinion_fixture(author_id: author.id)
      opinion2 = opinion_fixture(author_id: author.id)

      # Link opinions to voting
      {:ok, _} = Opinions.add_opinion_to_voting(opinion1, voting.id)
      {:ok, _} = Opinions.add_opinion_to_voting(opinion2, voting.id)

      # Fetch votings
      [fetched_voting] = Votings.list_votings_with_opinions_by_authors([author.id])

      # This Assertion should now pass with the fix
      assert length(fetched_voting.opinions) == 1
      [opinion] = fetched_voting.opinions
      # opinion2 was created last
      assert opinion.id == opinion2.id
    end
  end
end
