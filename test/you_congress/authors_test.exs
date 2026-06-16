defmodule YouCongress.AuthorsTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  alias YouCongress.Authors
  alias YouCongress.Workers.SetAuthorProfileImageFromXWorker

  describe "authors" do
    alias YouCongress.Authors.Author
    alias YouCongress.Accounts.User
    alias YouCongress.Delegations.Delegation
    alias YouCongress.Opinions.Opinion
    alias YouCongress.Repo
    alias YouCongress.VoteVerifications
    alias YouCongress.VoteVerifications.VoteVerification
    alias YouCongress.Votes
    alias YouCongress.Votes.Vote

    import YouCongress.AccountsFixtures
    import YouCongress.AuthorsFixtures
    import YouCongress.CountriesFixtures
    import YouCongress.DelegationsFixtures
    import YouCongress.OpinionsFixtures
    import YouCongress.StatementsFixtures
    import YouCongress.VotesFixtures

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

    test "merge_authors/2 keeps the author with more opinions, fills blank profile fields, moves links, and deletes the duplicate" do
      country = country_fixture(name: "Merge Country")

      survivor =
        author_fixture(%{
          name: "Survivor",
          bio: "Survivor bio",
          twitter_username: nil,
          twitter_id_str: nil,
          wikipedia_url: nil,
          profile_image_url: nil,
          country_id: nil,
          description: nil,
          followers_count: nil,
          friends_count: nil,
          verified: nil,
          location: nil,
          google_id: nil
        })

      duplicate =
        author_fixture(%{
          name: "Duplicate",
          bio: "Duplicate bio",
          twitter_username: "duplicate_author",
          twitter_id_str: "duplicate-twitter-id",
          wikipedia_url: "https://en.wikipedia.org/wiki/Duplicate_Author",
          profile_image_url: "https://example.com/duplicate.jpg",
          country_id: country.id,
          description: "Duplicate description",
          followers_count: 123,
          friends_count: 45,
          verified: true,
          location: "Madrid",
          google_id: "duplicate-google-id"
        })

      opinion_fixture(%{author_id: survivor.id, content: "survivor opinion 1"})
      opinion_fixture(%{author_id: survivor.id, content: "survivor opinion 2"})

      duplicate_opinion =
        opinion_fixture(%{author_id: duplicate.id, content: "duplicate opinion"})

      statement = statement_fixture()
      duplicate_vote = vote_fixture(%{author_id: duplicate.id, statement_id: statement.id})
      linked_user = user_for_author(duplicate)

      delegate = author_fixture()
      deleguee = author_fixture()
      delegation_fixture(%{deleguee_id: duplicate.id, delegate_id: delegate.id})
      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: duplicate.id})

      assert {:ok, %{author: merged_author, deleted_author: deleted_author}} =
               Authors.merge_authors(survivor.id, duplicate.id)

      assert merged_author.id == survivor.id
      assert deleted_author.id == duplicate.id
      assert merged_author.name == "Survivor"
      assert merged_author.bio == "Survivor bio"
      assert merged_author.twitter_username == "duplicate_author"
      assert merged_author.twitter_id_str == "duplicate-twitter-id"
      assert merged_author.wikipedia_url == "https://en.wikipedia.org/wiki/Duplicate_Author"
      assert merged_author.profile_image_url == "https://example.com/duplicate.jpg"
      assert merged_author.country_id == country.id
      assert merged_author.description == "Duplicate description"
      assert merged_author.followers_count == 123
      assert merged_author.friends_count == 45
      assert merged_author.verified == true
      assert merged_author.location == "Madrid"
      assert merged_author.google_id == "duplicate-google-id"

      assert Repo.get!(Opinion, duplicate_opinion.id).author_id == survivor.id
      assert Repo.get!(Vote, duplicate_vote.id).author_id == survivor.id
      assert Repo.get!(User, linked_user.id).author_id == survivor.id
      assert Repo.get_by(Delegation, deleguee_id: survivor.id, delegate_id: delegate.id)
      assert Repo.get_by(Delegation, deleguee_id: deleguee.id, delegate_id: survivor.id)
      refute Repo.get(Author, duplicate.id)
    end

    test "merge_authors/2 uses vote count as the tie breaker after opinion count" do
      first_author = author_fixture()
      second_author = author_fixture()

      vote_fixture(%{author_id: first_author.id})
      vote_fixture(%{author_id: second_author.id})
      vote_fixture(%{author_id: second_author.id})

      assert {:ok, %{author: merged_author, deleted_author: deleted_author}} =
               Authors.merge_authors(first_author.id, second_author.id)

      assert merged_author.id == second_author.id
      assert deleted_author.id == first_author.id
      refute Repo.get(Author, first_author.id)
    end

    test "merge_authors/2 keeps the first author when opinion and vote counts are tied" do
      first_author = author_fixture()
      second_author = author_fixture()

      assert {:ok, %{author: merged_author, deleted_author: deleted_author}} =
               Authors.merge_authors(first_author.id, second_author.id)

      assert merged_author.id == first_author.id
      assert deleted_author.id == second_author.id
      refute Repo.get(Author, second_author.id)
    end

    test "merge_authors/2 collapses duplicate votes and keeps their verifications" do
      survivor = author_fixture()
      duplicate = author_fixture()
      statement = statement_fixture()
      verifier = user_fixture()

      survivor_vote =
        vote_fixture(%{
          author_id: survivor.id,
          statement_id: statement.id,
          answer: :for,
          direct: false
        })

      duplicate_vote =
        vote_fixture(%{
          author_id: duplicate.id,
          statement_id: statement.id,
          answer: :against,
          direct: true
        })

      assert {:ok, verification} =
               VoteVerifications.create_verification(%{
                 vote_id: duplicate_vote.id,
                 user_id: verifier.id,
                 status: :verified,
                 comment: "Correct"
               })

      assert {:ok, %{author: merged_author}} = Authors.merge_authors(survivor.id, duplicate.id)

      merged_vote = Votes.get_by(%{author_id: merged_author.id, statement_id: statement.id})
      assert merged_vote.id == survivor_vote.id
      assert merged_vote.answer == :against
      assert merged_vote.direct == true
      assert merged_vote.verification_status == :verified

      refute Repo.get(Vote, duplicate_vote.id)
      assert Repo.get!(VoteVerification, verification.id).vote_id == survivor_vote.id
    end

    test "merge_authors/2 removes duplicate delegations instead of violating unique constraints" do
      survivor = author_fixture()
      duplicate = author_fixture()
      delegate = author_fixture()
      deleguee = author_fixture()

      delegation_fixture(%{deleguee_id: survivor.id, delegate_id: delegate.id})
      delegation_fixture(%{deleguee_id: duplicate.id, delegate_id: delegate.id})
      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: survivor.id})
      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: duplicate.id})

      assert {:ok, %{author: merged_author}} = Authors.merge_authors(survivor.id, duplicate.id)

      assert merged_author.id == survivor.id

      assert Repo.aggregate(
               from(d in Delegation,
                 where: d.deleguee_id == ^survivor.id and d.delegate_id == ^delegate.id
               ),
               :count,
               :id
             ) == 1

      assert Repo.aggregate(
               from(d in Delegation,
                 where: d.deleguee_id == ^deleguee.id and d.delegate_id == ^survivor.id
               ),
               :count,
               :id
             ) == 1

      refute Repo.get(Author, duplicate.id)
    end

    test "merge_authors/2 refreshes delegated votes that pointed at the duplicate author" do
      survivor = author_fixture()
      duplicate = author_fixture()
      deleguee = author_fixture()
      statement = statement_fixture()

      vote_fixture(%{
        author_id: survivor.id,
        statement_id: statement.id,
        answer: :for,
        direct: true
      })

      vote_fixture(%{
        author_id: duplicate.id,
        statement_id: statement.id,
        answer: :against,
        direct: true
      })

      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: duplicate.id})
      delegated_vote = Votes.get_by(%{author_id: deleguee.id, statement_id: statement.id})
      assert delegated_vote.answer == :against
      assert delegated_vote.direct == false

      assert {:ok, %{author: merged_author}} = Authors.merge_authors(survivor.id, duplicate.id)

      refreshed_vote = Votes.get_by(%{author_id: deleguee.id, statement_id: statement.id})
      assert refreshed_vote.answer == :for
      assert refreshed_vote.direct == false
      assert Repo.get_by(Delegation, deleguee_id: deleguee.id, delegate_id: merged_author.id)
      refute Repo.get(Author, duplicate.id)
    end

    test "merge_authors/2 rejects the same author id" do
      author = author_fixture()

      assert Authors.merge_authors(author.id, author.id) == {:error, :same_author}
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

    defp user_for_author(author) do
      %User{}
      |> User.twitter_registration_changeset(%{
        "email" => unique_user_email(),
        "author_id" => author.id
      })
      |> Repo.insert!()
    end
  end
end
