defmodule YouCongress.OpinionsSearchTest do
  use YouCongress.DataCase

  alias YouCongress.Opinions
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures

  describe "opinions search" do
    test "search/1 finds opinion by mixed content and author name" do
      author = author_fixture(name: "Isaac Asimov")
      opinion = opinion_fixture(
        author_id: author.id,
        content: "Science gathers knowledge faster than society gathers wisdom."
      )

      # Search matches both author "Asimov" and content "knowledge"
      assert [result] = Opinions.list_opinions(search: "Asimov knowledge")
      assert result.id == opinion.id
    end
  end
end
