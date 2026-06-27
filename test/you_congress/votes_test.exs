defmodule YouCongress.VotesTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.CountriesFixtures
  import YouCongress.DelegationsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  import YouCongress.OpinionsFixtures

  alias YouCongress.Repo
  alias YouCongress.Accounts
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongress.Workers.RefreshAuthorStatementDelegatedVotesWorker

  describe "votes" do
    @invalid_attrs %{author_id: nil}

    test "list_votes/0 returns all votes" do
      vote = vote_fixture()
      assert Votes.list_votes() == [vote]
    end

    test "get_vote!/1 returns the vote with given id" do
      vote = vote_fixture()
      assert Votes.get_vote!(vote.id) == vote
    end

    test "create_vote/1 with valid data creates a vote" do
      valid_attrs = %{
        opinion_id: opinion_fixture().id,
        author_id: author_fixture().id,
        statement_id: statement_fixture().id,
        answer: :for
      }

      assert {:ok, %Vote{}} = Votes.create_vote(valid_attrs)
    end

    test "list_top_sourced_statement_authors/2 returns wikipedia authors ordered by followers count" do
      unique = System.unique_integer([:positive])
      statement = statement_fixture()
      other_statement = statement_fixture()

      low =
        author_fixture(%{
          name: "Low Reach",
          wikipedia_url: "https://en.wikipedia.org/wiki/Low_Reach_#{unique}",
          followers_count: 10
        })

      top =
        author_fixture(%{
          name: "Top Reach",
          wikipedia_url: "https://en.wikipedia.org/wiki/Top_Reach_#{unique}",
          followers_count: 1_000
        })

      middle =
        author_fixture(%{
          name: "Middle Reach",
          wikipedia_url: "https://en.wikipedia.org/wiki/Middle_Reach_#{unique}",
          followers_count: 500
        })

      no_wiki =
        author_fixture(%{
          name: "No Wiki",
          wikipedia_url: nil,
          followers_count: 2_000
        })

      unsourced =
        author_fixture(%{
          name: "Unsourced",
          wikipedia_url: "https://en.wikipedia.org/wiki/Unsourced_#{unique}",
          followers_count: 3_000
        })

      twin =
        author_fixture(%{
          name: "Twin Quote",
          wikipedia_url: "https://en.wikipedia.org/wiki/Twin_Quote_#{unique}",
          followers_count: 5_000
        })

      other_statement_author =
        author_fixture(%{
          name: "Other Statement",
          wikipedia_url: "https://en.wikipedia.org/wiki/Other_Statement_#{unique}",
          followers_count: 4_000
        })

      create_vote_with_opinion(statement, low)
      create_vote_with_opinion(statement, top)
      create_vote_with_opinion(statement, middle)
      create_vote_with_opinion(statement, no_wiki)
      create_vote_with_opinion(statement, unsourced, source_url: nil)
      create_vote_with_opinion(statement, twin, twin: true)
      create_vote_with_opinion(other_statement, other_statement_author)

      assert statement.id
             |> Votes.list_top_sourced_statement_authors(3)
             |> Enum.map(& &1.name) == ["Top Reach", "Middle Reach", "Low Reach"]
    end

    test "create_vote/1 by the author marks the vote answer as endorsed" do
      user = user_fixture()
      statement = statement_fixture()

      assert {:ok, %Vote{} = vote} =
               Votes.create_vote(%{
                 author_id: user.author_id,
                 user_id: user.id,
                 statement_id: statement.id,
                 answer: :for,
                 direct: true
               })

      assert Votes.get_vote!(vote.id).verification_status == :endorsed
    end

    test "update_vote/2 by the author marks an unsourced comment vote as endorsed" do
      user = user_fixture()
      statement = statement_fixture()

      opinion =
        opinion_fixture(%{
          author_id: user.author_id,
          user_id: user.id,
          source_url: nil,
          twin: false
        })

      vote =
        vote_fixture(%{
          author_id: user.author_id,
          statement_id: statement.id,
          answer: :abstain,
          direct: true
        })

      assert {:ok, %Vote{} = vote} =
               Votes.update_vote(vote, %{
                 opinion_id: opinion.id,
                 user_id: user.id,
                 answer: :for,
                 twin: false
               })

      assert Votes.get_vote!(vote.id).verification_status == :endorsed
    end

    test "create_vote/1 enqueues delegated vote refresh jobs for direct votes" do
      delegate = author_fixture()
      deleguee = author_fixture()
      statement = statement_fixture()

      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: delegate.id})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Vote{}} =
                 Votes.create_vote(%{
                   author_id: delegate.id,
                   statement_id: statement.id,
                   answer: :for,
                   direct: true
                 })

        assert_enqueued(
          worker: RefreshAuthorStatementDelegatedVotesWorker,
          args: %{"author_id" => deleguee.id, "statement_id" => statement.id}
        )
      end)
    end

    test "create_vote/1 does not enqueue delegated vote refresh jobs for delegated votes" do
      delegate = author_fixture()
      deleguee = author_fixture()
      statement = statement_fixture()

      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: delegate.id})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Vote{}} =
                 Votes.create_vote(%{
                   author_id: delegate.id,
                   statement_id: statement.id,
                   answer: :for,
                   direct: false
                 })

        refute_enqueued(worker: RefreshAuthorStatementDelegatedVotesWorker)
      end)
    end

    test "create_vote/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Votes.create_vote(@invalid_attrs)
    end

    test "update_vote/2 with valid data updates the vote" do
      vote = vote_fixture()
      opinion = opinion_fixture()
      update_attrs = %{opinion_id: opinion.id}

      assert {:ok, %Vote{} = vote} = Votes.update_vote(vote, update_attrs)
      assert vote.opinion_id == opinion.id
    end

    test "update_vote/2 enqueues delegated vote refresh jobs when a direct vote is introduced" do
      delegate = author_fixture()
      deleguee = author_fixture()
      statement = statement_fixture()

      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: delegate.id})

      vote =
        %Vote{}
        |> Vote.changeset(%{
          author_id: delegate.id,
          statement_id: statement.id,
          answer: :for,
          direct: false
        })
        |> Repo.insert!()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Vote{} = updated_vote} =
                 Votes.update_vote(vote, %{direct: true, answer: :against})

        assert updated_vote.direct

        assert_enqueued(
          worker: RefreshAuthorStatementDelegatedVotesWorker,
          args: %{"author_id" => deleguee.id, "statement_id" => statement.id}
        )
      end)
    end

    test "update_vote/2 with invalid data returns error changeset" do
      vote = vote_fixture()
      assert {:error, %Ecto.Changeset{}} = Votes.update_vote(vote, @invalid_attrs)
      assert vote == Votes.get_vote!(vote.id)
    end

    test "delete_vote/1 deletes the vote" do
      vote = vote_fixture()
      assert {:ok, %Vote{}} = Votes.delete_vote(vote)
      assert_raise Ecto.NoResultsError, fn -> Votes.get_vote!(vote.id) end
    end

    test "delete_vote/1 restores the author's delegated fallback vote after deleting a direct vote" do
      delegate = author_fixture()
      deleguee = author_fixture()
      statement = statement_fixture()

      delegation_fixture(%{deleguee_id: deleguee.id, delegate_id: delegate.id})

      direct_vote =
        vote_fixture(%{
          author_id: deleguee.id,
          statement_id: statement.id,
          answer: :for,
          direct: true
        })

      assert {:ok, %Vote{}} =
               Votes.create_vote(%{
                 author_id: delegate.id,
                 statement_id: statement.id,
                 answer: :against,
                 direct: true
               })

      assert {:ok, %Vote{}} = Votes.delete_vote(direct_vote)

      fallback_vote = Votes.get_by(%{statement_id: statement.id, author_id: deleguee.id})
      assert fallback_vote
      assert fallback_vote.answer == :against
      assert fallback_vote.direct == false
    end

    test "change_vote/1 returns a vote changeset" do
      vote = vote_fixture()
      assert %Ecto.Changeset{} = Votes.change_vote(vote)
    end

    test "count/0 returns the number of votes" do
      vote_fixture()
      vote_fixture()
      assert Votes.count() == 2
    end

    test "count_by_author_id/1 returns the number of votes by author id" do
      author = author_fixture()
      vote_fixture(author_id: author.id)
      vote_fixture()
      vote_fixture(author_id: author.id)
      assert Votes.count_by_author_id(author.id) == 2
    end

    test "VoteFrequencies.get_by_country/1 groups statement votes by country" do
      statement = statement_fixture()
      spain = country_fixture(%{name: "Spain"})
      france = country_fixture(%{name: "France"})

      spain_for_1 = author_fixture(%{country_id: spain.id})
      spain_for_2 = author_fixture(%{country_id: spain.id})
      spain_abstain = author_fixture(%{country_id: spain.id})
      france_against = author_fixture(%{country_id: france.id})
      unknown_for = author_fixture(%{country_id: nil})

      vote_fixture(%{statement_id: statement.id, author_id: spain_for_1.id, answer: :for})
      vote_fixture(%{statement_id: statement.id, author_id: spain_for_2.id, answer: :for})
      vote_fixture(%{statement_id: statement.id, author_id: spain_abstain.id, answer: :abstain})
      vote_fixture(%{statement_id: statement.id, author_id: france_against.id, answer: :against})
      vote_fixture(%{statement_id: statement.id, author_id: unknown_for.id, answer: :for})

      assert [
               %{
                 country_id: spain_id,
                 country_name: "Spain",
                 total_votes: 3,
                 vote_frequencies: %{
                   for: {2, 67},
                   abstain: {1, 33},
                   against: {0, 0}
                 }
               },
               %{
                 country_id: france_id,
                 country_name: "France",
                 total_votes: 1,
                 vote_frequencies: %{
                   for: {0, 0},
                   abstain: {0, 0},
                   against: {1, 100}
                 }
               },
               %{
                 country_id: nil,
                 country_name: "Unknown country",
                 total_votes: 1,
                 vote_frequencies: %{
                   for: {1, 100},
                   abstain: {0, 0},
                   against: {0, 0}
                 }
               }
             ] = VoteFrequencies.get_by_country(statement.id)

      assert spain_id == spain.id
      assert france_id == france.id
    end

    test "VoteFrequencies.get_by_country/2 filters vote type and source" do
      statement = statement_fixture()
      phone_country = country_fixture(%{name: "Phone Verified Spain", phone_prefix: "+34"})
      declared_country = country_fixture(%{name: "Declared Country", phone_prefix: "+999"})
      quote_country = country_fixture(%{name: "Quote Country", phone_prefix: "+33"})

      unique = System.unique_integer([:positive])

      phone_user =
        user_fixture(%{}, %{
          name: "Phone User #{unique}",
          twitter_username: "phone_user_#{unique}",
          bio: "Bio",
          wikipedia_url: "https://en.wikipedia.org/wiki/Phone_User_#{unique}",
          twin_origin: false,
          country_id: declared_country.id
        })

      {:ok, phone_user} = Accounts.update_user_phone_number(phone_user, "+34123456789")
      {:ok, phone_user} = Accounts.confirm_user_phone(phone_user)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: phone_user.author_id,
        answer: :for
      })

      direct_quote_author = author_fixture(%{country_id: quote_country.id})
      direct_quote = opinion_fixture(%{author_id: direct_quote_author.id})

      vote_fixture(%{
        statement_id: statement.id,
        author_id: direct_quote_author.id,
        opinion_id: direct_quote.id,
        answer: :against,
        direct: true
      })

      delegated_quote_author = author_fixture(%{country_id: quote_country.id})
      delegated_quote = opinion_fixture(%{author_id: delegated_quote_author.id})

      vote_fixture(%{
        statement_id: statement.id,
        author_id: delegated_quote_author.id,
        opinion_id: delegated_quote.id,
        answer: :against,
        direct: false
      })

      assert [
               %{
                 country_id: phone_country_id,
                 country_name: "Phone Verified Spain",
                 total_votes: 1,
                 vote_frequencies: %{for: {1, 100}, abstain: {0, 0}, against: {0, 0}}
               }
             ] =
               VoteFrequencies.get_by_country(statement.id, %{
                 direct: true,
                 delegated: false,
                 quotes: false,
                 email_verified: false,
                 phone_verified: true
               })

      assert phone_country_id == phone_country.id

      assert [
               %{
                 country_id: quote_country_id,
                 country_name: "Quote Country",
                 total_votes: 1,
                 vote_frequencies: %{for: {0, 0}, abstain: {0, 0}, against: {1, 100}}
               }
             ] =
               VoteFrequencies.get_by_country(statement.id, %{
                 direct: false,
                 delegated: true,
                 quotes: true,
                 email_verified: false,
                 phone_verified: false
               })

      assert quote_country_id == quote_country.id
    end
  end

  defp create_vote_with_opinion(statement, author, opts \\ []) do
    source_url =
      if Keyword.has_key?(opts, :source_url) do
        Keyword.fetch!(opts, :source_url)
      else
        "https://example.com/source/#{author.id}"
      end

    twin = Keyword.get(opts, :twin, false)

    opinion =
      opinion_fixture(%{
        author_id: author.id,
        source_url: source_url,
        twin: twin
      })

    {:ok, vote} =
      Votes.create_vote(%{
        author_id: author.id,
        statement_id: statement.id,
        opinion_id: opinion.id,
        answer: :for,
        twin: twin
      })

    vote
  end
end
