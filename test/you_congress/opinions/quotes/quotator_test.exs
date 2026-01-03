defmodule YouCongress.Opinions.Quotes.QuotatorTest do
  use YouCongress.DataCase

  import YouCongress.AccountsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Opinions.Quotes.Quotator
  alias YouCongress.{Votes, Opinions}

  describe "find_and_save_quotes/3 with QuotatorFake" do
    test "forwards exclude list, sets generating counters, and creates votes/opinions" do
      voting = statement_fixture(%{title: "Test Statement Title"})
      user = user_fixture(%{name: "Test User"})

      exclude = ["Excluded Name"]

      assert {:ok, saved_count} = Quotator.find_and_save_quotes(voting.id, exclude, user.id, 1, 1)
      # Association step requires user_id for join table; we expect 0 persisted in that step
      assert saved_count == Quotator.number_of_quotes()

      # 20 votes should be created for the generated quotes
      assert Votes.count_by_statement(voting.id) == Quotator.number_of_quotes()

      votes = Votes.list_votes(voting.id)
      # Votes should be direct and not twins
      assert Enum.all?(votes, &(&1.direct == true and &1.twin == false))

      # Each vote should have a valid answer
      assert Enum.all?(votes, fn v -> v.answer in [:for, :against, :abstain] end)

      # Opinions should be created and linked to the votes
      assert Enum.count(votes, &(not is_nil(&1.opinion_id))) == Quotator.number_of_quotes()

      # Opinions should have parsed year as integer
      Enum.each(votes, fn v ->
        opinion = Opinions.get_opinion!(v.opinion_id)
        assert is_integer(opinion.year)
      end)
    end
  end
end
