defmodule YouCongress.StatementsFilterTest do
  use YouCongress.DataCase

  alias YouCongress.Statements
  alias YouCongress.Opinions

  import YouCongress.StatementsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures

  describe "list_statements_with_opinions_by_authors/1 returns multiple opinions" do
    test "returns multiple opinions per author if they exist (current behavior)" do
      author = author_fixture()
      statement = statement_fixture()

      # Create 2 opinions for the same author
      opinion1 = opinion_fixture(author_id: author.id)
      opinion2 = opinion_fixture(author_id: author.id)

      # Link opinions to statement
      {:ok, _} = Opinions.add_opinion_to_statement(opinion1, statement.id)
      {:ok, _} = Opinions.add_opinion_to_statement(opinion2, statement.id)

      # Fetch statements
      [fetched_statement] = Statements.list_statements_with_opinions_by_authors([author.id])

      # This Assertion should now pass with the fix
      assert length(fetched_statement.opinions) == 1
      [opinion] = fetched_statement.opinions
      # opinion2 was created last
      assert opinion.id == opinion2.id
    end
  end
end
