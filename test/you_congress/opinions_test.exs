defmodule YouCongress.OpinionsTest do
  use YouCongress.DataCase

  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.OpinionsFixtures

  import YouCongress.Opinions.AnswersFixtures

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion

  describe "opinions" do
    @invalid_attrs %{opinion: nil}

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
        opinion: "some opinion",
        author_id: author_fixture().id,
        voting_id: voting_fixture().id,
        answer_id: answer_fixture().id
      }

      assert {:ok, %Opinion{} = opinion} = Opinions.create_opinion(valid_attrs)
      assert opinion.opinion == "some opinion"
    end

    test "create_opinion/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Opinions.create_opinion(@invalid_attrs)
    end

    test "update_opinion/2 with valid data updates the opinion" do
      opinion = opinion_fixture()
      update_attrs = %{opinion: "some updated opinion"}

      assert {:ok, %Opinion{} = opinion} = Opinions.update_opinion(opinion, update_attrs)
      assert opinion.opinion == "some updated opinion"
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

    test "change_opinion/1 returns a opinion changeset" do
      opinion = opinion_fixture()
      assert %Ecto.Changeset{} = Opinions.change_opinion(opinion)
    end
  end
end
