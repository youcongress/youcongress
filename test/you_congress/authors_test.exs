defmodule YouCongress.AuthorsTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  alias YouCongress.Authors
  alias YouCongress.Workers.SetAuthorProfileImageFromXWorker

  describe "authors" do
    alias YouCongress.Authors.Author

    import YouCongress.AuthorsFixtures
    import YouCongress.CountriesFixtures

    @invalid_attrs %{
      bio: nil,
      country_id: nil,
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
      assert Authors.list_authors(search: "albert") == [author2]
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

    test "list_authors/1 supports limit" do
      a1 = author_fixture(name: "Ada Lovelace")
      a2 = author_fixture(name: "Alan Turing")
      a3 = author_fixture(name: "Grace Hopper")

      results = Authors.list_authors(limit: 2)

      assert length(results) == 2
      assert Enum.all?(results, &(&1.id in [a1.id, a2.id, a3.id]))
    end

    test "get_author!/1 returns the author with given id" do
      author = author_fixture()
      assert Authors.get_author!(author.id) == author
    end

    test "create_author/1 with valid data creates a author" do
      country = country_fixture(name: "Some Country")

      valid_attrs = %{
        bio: "some bio",
        country_id: country.id,
        twin_origin: true,
        name: "some name",
        twitter_username: "some twitter_username",
        wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
      }

      assert {:ok, %Author{} = author} = Authors.create_author(valid_attrs)
      assert author.bio == "some bio"
      assert author.country_id == country.id
      assert author.twin_origin == true
      assert author.name == "some name"
      assert author.twitter_username == "some twitter_username"
      assert author.wikipedia_url == "https://en.wikipedia.org/wiki/whatever"
    end

    test "create_author/1 resolves legacy country names and ISO codes" do
      country = country_fixture(name: "United States", iso_alpha2: "US", iso_alpha3: "USA")

      valid_attrs = %{
        bio: "some bio",
        country: "USA",
        twin_origin: true,
        name: "some name",
        twitter_username: "some twitter_username",
        wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
      }

      assert {:ok, %Author{} = author} = Authors.create_author(valid_attrs)
      assert author.country_id == country.id
    end

    test "create_author/1 rejects unknown legacy country names" do
      valid_attrs = %{
        bio: "some bio",
        country: "Wonderland",
        twin_origin: true,
        name: "some name",
        twitter_username: "some twitter_username",
        wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
      }

      assert {:error, changeset} = Authors.create_author(valid_attrs)
      assert "does not match an existing country" in errors_on(changeset).country_id
    end

    test "create_author/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Authors.create_author(@invalid_attrs)
    end

    test "find_by_name_or_create/1 returns a stable existing author when names are duplicated" do
      first_author = author_fixture(name: "Brad Smith", twitter_username: "brad_smith_one")
      _second_author = author_fixture(name: "Brad Smith", twitter_username: "brad_smith_two")

      assert {:ok, found_author} =
               Authors.find_by_name_or_create(%{
                 "name" => "Brad Smith",
                 "bio" => "Technology executive",
                 "twin_origin" => false
               })

      assert found_author.id == first_author.id
    end

    test "find_by_twitter_username_or_create/1 is case insensitive" do
      author = author_fixture(name: "Brad Smith", twitter_username: "BradSmith")

      assert {:ok, found_author} =
               Authors.find_by_twitter_username_or_create(%{
                 "name" => "Brad Smith",
                 "twitter_username" => "bradsmith",
                 "twin_origin" => false
               })

      assert found_author.id == author.id
    end

    test "update_author/2 with valid data updates the author" do
      author = author_fixture()
      country = country_fixture(name: "Updated Country")

      update_attrs = %{
        bio: "some updated bio",
        country_id: country.id,
        twin_origin: false,
        name: "some updated name",
        twitter_username: "some updated twitter_username",
        wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
      }

      assert {:ok, %Author{} = author} = Authors.update_author(author, update_attrs)
      assert author.bio == "some updated bio"
      assert author.country_id == country.id
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

    test "create_author/1 enqueues a profile image fetch when there is an X username but no picture" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        author = author_fixture(twitter_username: "some_username")

        assert_enqueued(
          worker: SetAuthorProfileImageFromXWorker,
          args: %{author_id: author.id}
        )
      end)
    end

    test "create_author/1 does not enqueue a profile image fetch when the author already has a picture" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        author =
          author_fixture(
            twitter_username: "some_username",
            profile_image_url: "https://pbs.twimg.com/profile_images/123/abc.jpg"
          )

        refute_enqueued(
          worker: SetAuthorProfileImageFromXWorker,
          args: %{author_id: author.id}
        )
      end)
    end

    test "create_author/1 does not enqueue a profile image fetch without an X username" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        author = author_fixture(twitter_username: nil)

        refute_enqueued(
          worker: SetAuthorProfileImageFromXWorker,
          args: %{author_id: author.id}
        )
      end)
    end

    test "update_author/2 enqueues a profile image fetch when there is an X username but no picture" do
      author = author_fixture(twitter_username: nil)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, author} = Authors.update_author(author, %{twitter_username: "some_username"})

        assert_enqueued(
          worker: SetAuthorProfileImageFromXWorker,
          args: %{author_id: author.id}
        )
      end)
    end

    test "update_author/2 does not enqueue a profile image fetch when the author already has a picture" do
      author =
        author_fixture(
          twitter_username: "some_username",
          profile_image_url: "https://pbs.twimg.com/profile_images/123/abc.jpg"
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, author} = Authors.update_author(author, %{bio: "updated bio"})

        refute_enqueued(
          worker: SetAuthorProfileImageFromXWorker,
          args: %{author_id: author.id}
        )
      end)
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

    test "set_profile_image_from_x/1 returns error when author has no twitter_username" do
      author = author_fixture(twitter_username: nil)

      assert Authors.set_profile_image_from_x(author) == {:error, :no_twitter_username}
    end
  end
end
