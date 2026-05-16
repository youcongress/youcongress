defmodule YouCongress.VotesTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AuthorsFixtures
  import YouCongress.DelegationsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  import YouCongress.OpinionsFixtures

  alias YouCongress.Repo
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
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
  end
end
