defmodule YouCongress.OpinionsTest do
  use YouCongress.DataCase

  alias YouCongress.Opinions

  describe "opinions" do
    alias YouCongress.Opinions.Opinion

    import YouCongress.OpinionsFixtures
    import YouCongress.VotingsFixtures

    @invalid_attrs %{source_url: nil, content: nil, twin: nil}

    test "list_opinions/0 returns all opinions" do
      opinion = opinion_fixture()
      assert Opinions.list_opinions() == [opinion]
    end

    test "get_opinion!/1 returns the opinion with given id" do
      opinion = opinion_fixture()
      assert Opinions.get_opinion!(opinion.id) == opinion
    end

    test "create_opinion/1 with valid data creates a opinion" do
      valid_attrs = %{
        source_url: "https://some.source_url.com",
        content: "some content",
        twin: true,
        voting_id: voting_fixture().id
      }

      assert {:ok, %{opinion: %Opinion{} = opinion}} = Opinions.create_opinion(valid_attrs)
      assert opinion.source_url == "https://some.source_url.com"
      assert opinion.content == "some content"
      assert opinion.twin == true
    end

    test "create_opinion/1 with invalid data returns error changeset" do
      assert {:error, :opinion, %Ecto.Changeset{}, %{}} = Opinions.create_opinion(@invalid_attrs)
    end

    test "update_opinion/2 with valid data updates the opinion" do
      opinion = opinion_fixture()

      update_attrs = %{
        source_url: "https://some.source_url.com",
        content: "some updated content",
        twin: false
      }

      assert {:ok, %Opinion{} = opinion} = Opinions.update_opinion(opinion, update_attrs)
      assert opinion.source_url == "https://some.source_url.com"
      assert opinion.content == "some updated content"
      assert opinion.twin == false
    end

    test "update_opinion/2 with invalid data returns error changeset" do
      opinion = opinion_fixture()
      assert {:error, %Ecto.Changeset{}} = Opinions.update_opinion(opinion, @invalid_attrs)
      assert opinion == Opinions.get_opinion!(opinion.id)
    end

    test "delete_opinion/1 deletes the opinion" do
      opinion = opinion_fixture()
      assert {:ok, %Opinion{}} = Opinions.delete_opinion(opinion)
      assert_raise Ecto.NoResultsError, fn -> Opinions.get_opinion!(opinion.id) end
    end

    test "delete_opinion/1 deletes associated votes via database cascade" do
      alias YouCongress.Votes.Vote
      alias YouCongress.Repo

      opinion = opinion_fixture()
      voting = voting_fixture()

      # Create a vote associated with the opinion
      vote_attrs = %{
        author_id: opinion.author_id,
        voting_id: voting.id,
        answer_id: 1,
        opinion_id: opinion.id
      }

      {:ok, vote} = %Vote{}
      |> Vote.changeset(vote_attrs)
      |> Repo.insert()

      # Verify the vote exists
      assert Repo.get(Vote, vote.id) != nil

      # Delete the opinion (votes will be deleted by database cascade)
      assert {:ok, %Opinion{}} = Opinions.delete_opinion(opinion)

      # Verify the vote is also deleted by database cascade
      assert Repo.get(Vote, vote.id) == nil
    end

    test "delete_opinion_and_descendants/1 deletes opinion and associated votes via database cascade" do
      alias YouCongress.Votes.Vote
      alias YouCongress.Repo

      opinion = opinion_fixture()
      voting = voting_fixture()

      # Create a vote associated with the opinion
      vote_attrs = %{
        author_id: opinion.author_id,
        voting_id: voting.id,
        answer_id: 1,
        opinion_id: opinion.id
      }

      {:ok, vote} = %Vote{}
      |> Vote.changeset(vote_attrs)
      |> Repo.insert()

      # Verify the vote exists
      assert Repo.get(Vote, vote.id) != nil

      # Delete the opinion and descendants (votes will be deleted by database cascade)
      {count, _} = Opinions.delete_opinion_and_descendants(opinion)
      assert count == 1

      # Verify the vote is also deleted by database cascade
      assert Repo.get(Vote, vote.id) == nil
    end

    test "change_opinion/1 returns a opinion changeset" do
      opinion = opinion_fixture()
      assert %Ecto.Changeset{} = Opinions.change_opinion(opinion)
    end
  end
end
