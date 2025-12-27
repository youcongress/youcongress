defmodule YouCongress.AuthorsSearchTest do
  use YouCongress.DataCase

  alias YouCongress.Authors
  import YouCongress.AuthorsFixtures

  describe "authors search" do
    test "search/1 finds author by mixed name and twitter username" do
      author =
        author_fixture(
          name: "Isaac Asimov",
          twitter_username: "the_good_doctor"
        )

      # Search matches "Asimov" (name) and "doctor" (twitter)
      assert [result] = Authors.list_authors(search: "Asimov doctor")
      assert result.id == author.id
    end
  end
end
