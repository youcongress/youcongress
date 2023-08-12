defmodule YouCongress.AuthorsTest do
  use YouCongress.DataCase

  alias YouCongress.Authors

  describe "authors" do
    alias YouCongress.Authors.Author

    import YouCongress.AuthorsFixtures

    @invalid_attrs %{
      bio: nil,
      country: nil,
      is_twin: nil,
      name: nil,
      twitter_url: nil,
      wikipedia_url: nil
    }

    test "list_authors/0 returns all authors" do
      author = author_fixture()
      assert Authors.list_authors() == [author]
    end

    test "get_author!/1 returns the author with given id" do
      author = author_fixture()
      assert Authors.get_author!(author.id) == author
    end

    test "create_author/1 with valid data creates a author" do
      valid_attrs = %{
        bio: "some bio",
        country: "some country",
        is_twin: true,
        name: "some name",
        twitter_url: "some twitter_url",
        wikipedia_url: "some wikipedia_url"
      }

      assert {:ok, %Author{} = author} = Authors.create_author(valid_attrs)
      assert author.bio == "some bio"
      assert author.country == "some country"
      assert author.is_twin == true
      assert author.name == "some name"
      assert author.twitter_url == "some twitter_url"
      assert author.wikipedia_url == "some wikipedia_url"
    end

    test "create_author/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Authors.create_author(@invalid_attrs)
    end

    test "update_author/2 with valid data updates the author" do
      author = author_fixture()

      update_attrs = %{
        bio: "some updated bio",
        country: "some updated country",
        is_twin: false,
        name: "some updated name",
        twitter_url: "some updated twitter_url",
        wikipedia_url: "some updated wikipedia_url"
      }

      assert {:ok, %Author{} = author} = Authors.update_author(author, update_attrs)
      assert author.bio == "some updated bio"
      assert author.country == "some updated country"
      assert author.is_twin == false
      assert author.name == "some updated name"
      assert author.twitter_url == "some updated twitter_url"
      assert author.wikipedia_url == "some updated wikipedia_url"
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
  end
end
