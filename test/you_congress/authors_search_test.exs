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

    test "search/1 finds authors by YouCongress username and bio" do
      author =
        author_fixture(
          name: "Ada Energy",
          username: "ada_energy",
          bio: "Writes about advanced reactors and clean grids"
        )

      assert [username_result] = Authors.list_authors(search: "ada_energy")
      assert username_result.id == author.id

      assert [bio_result] = Authors.list_authors(search: "advanced reactors")
      assert bio_result.id == author.id
    end

    test "search relevance favors a name match over a bio substring" do
      ada =
        author_fixture(
          name: "Ada Colau",
          username: "ada_colau",
          bio: "Former mayor of Barcelona"
        )

      elon =
        author_fixture(
          name: "Elon Musk",
          username: "elon_musk",
          bio: "Technology entrepreneur"
        )

      results =
        Authors.list_authors(
          search: "elon",
          order_by_search_relevance: "elon"
        )

      assert Enum.map(results, & &1.id) == [elon.id, ada.id]
    end
  end
end
