defmodule YouCongress.AuthorsTest do
  use YouCongress.DataCase

  alias YouCongress.Authors

  describe "authors" do
    alias YouCongress.Authors.Author

    import YouCongress.AuthorsFixtures

    @invalid_attrs %{
      bio: nil,
      country: nil,
      twin_origin: nil,
      name: nil,
      twitter_username: nil,
      wikipedia_url: nil
    }

    test "list_authors/0 returns all authors" do
      author = author_fixture()
      assert Authors.list_authors() == [author]
    end

    test "list_authors/1 with search returns matched authors" do
      author1 = author_fixture(name: "Stephen Hawking")
      author2 = author_fixture(name: "Albert Einstein")

      assert Authors.list_authors(search: "hawki") == [author1]
      assert Authors.list_authors(search: "steph") == [author1]
      assert Authors.list_authors(search: "einstein") == [author2]
      assert Authors.list_authors(search: "bert") == [author2]
    end

    test "list_authors/1 with multiple search terms (AND logic)" do
      author = author_fixture(name: "Stephen Hawking")

      # "hawking" and "stephen" both present
      assert Authors.list_authors(search: "stephen hawking") == [author]
      # Order shouldn't matter
      assert Authors.list_authors(search: "hawking stephen") == [author]
      # Partial matching for both
      assert Authors.list_authors(search: "hawki steph") == [author]
    end

    test "get_author!/1 returns the author with given id" do
      author = author_fixture()
      assert Authors.get_author!(author.id) == author
    end

    test "create_author/1 with valid data creates a author" do
      valid_attrs = %{
        bio: "some bio",
        country: "some country",
        twin_origin: true,
        name: "some name",
        twitter_username: "some twitter_username",
        wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
      }

      assert {:ok, %Author{} = author} = Authors.create_author(valid_attrs)
      assert author.bio == "some bio"
      assert author.country == "some country"
      assert author.twin_origin == true
      assert author.name == "some name"
      assert author.twitter_username == "some twitter_username"
      assert author.wikipedia_url == "https://en.wikipedia.org/wiki/whatever"
    end

    test "create_author/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Authors.create_author(@invalid_attrs)
    end

    test "update_author/2 with valid data updates the author" do
      author = author_fixture()

      update_attrs = %{
        bio: "some updated bio",
        country: "some updated country",
        twin_origin: false,
        name: "some updated name",
        twitter_username: "some updated twitter_username",
        wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
      }

      assert {:ok, %Author{} = author} = Authors.update_author(author, update_attrs)
      assert author.bio == "some updated bio"
      assert author.country == "some updated country"
      assert author.twin_origin == false
      assert author.name == "some updated name"
      assert author.twitter_username == "some updated twitter_username"
      assert author.wikipedia_url == "https://en.wikipedia.org/wiki/whatever"
    end

    test "update_author/2 with invalid data returns error changeset" do
      author = author_fixture()
      assert {:error, %Ecto.Changeset{}} = Authors.update_author(author, @invalid_attrs)
      assert author == Authors.get_author!(author.id)
    end

    test "delete_author/1 deletes the author" do
      author = author_fixture()
      assert {:ok, %Author{}} = Authors.delete_author(author)
      assert_raise Ecto.NoResultsError, fn -> Authors.get_author!(author.id) end
    end

    test "change_author/1 returns a author changeset" do
      author = author_fixture()
      assert %Ecto.Changeset{} = Authors.change_author(author)
    end

    test "get_author_by_twitter_id_str_or_username/2 returns author by twitter_id_str" do
      author = author_fixture(twitter_id_str: "123456789", twitter_username: "user1")

      found = Authors.get_author_by_twitter_id_str_or_username("123456789", "other_username")
      assert found.id == author.id
    end

    test "get_author_by_twitter_id_str_or_username/2 falls back to twitter_username" do
      author = author_fixture(twitter_username: "fallback_author")

      found = Authors.get_author_by_twitter_id_str_or_username(nil, "fallback_author")
      assert found.id == author.id
    end

    test "get_author_by_twitter_id_str_or_username/2 prefers twitter_id_str over username" do
      author1 = author_fixture(twitter_id_str: "111", twitter_username: "author_one")
      _author2 = author_fixture(twitter_id_str: "222", twitter_username: "author_two")

      # Should find author1 by twitter_id_str even though author_two username is passed
      found = Authors.get_author_by_twitter_id_str_or_username("111", "author_two")
      assert found.id == author1.id
    end

    test "get_author_by_twitter_id_str_or_username/2 returns nil for both nil" do
      assert Authors.get_author_by_twitter_id_str_or_username(nil, nil) == nil
    end

    test "get_author_by_twitter_id_str_or_username/2 returns nil when not found" do
      assert Authors.get_author_by_twitter_id_str_or_username("nonexistent", "nonexistent") == nil
    end

    test "get_author_by_twitter_id_str_or_username/2 is case insensitive for username" do
      author = author_fixture(twitter_username: "CaseSensitive")

      found = Authors.get_author_by_twitter_id_str_or_username(nil, "casesensitive")
      assert found.id == author.id
    end
  end
end
