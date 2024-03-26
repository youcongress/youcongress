defmodule YouCongress.OpinionsTest do
  use YouCongress.DataCase

  alias YouCongress.Opinions

  describe "opinions" do
    alias YouCongress.Opinions.Opinion

    import YouCongress.OpinionsFixtures

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
      valid_attrs = %{source_url: "some source_url", content: "some content", twin: true}

      assert {:ok, %Opinion{} = opinion} = Opinions.create_opinion(valid_attrs)
      assert opinion.source_url == "some source_url"
      assert opinion.content == "some content"
      assert opinion.twin == true
    end

    test "create_opinion/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Opinions.create_opinion(@invalid_attrs)
    end

    test "update_opinion/2 with valid data updates the opinion" do
      opinion = opinion_fixture()
      update_attrs = %{source_url: "some updated source_url", content: "some updated content", twin: false}

      assert {:ok, %Opinion{} = opinion} = Opinions.update_opinion(opinion, update_attrs)
      assert opinion.source_url == "some updated source_url"
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

    test "change_opinion/1 returns a opinion changeset" do
      opinion = opinion_fixture()
      assert %Ecto.Changeset{} = Opinions.change_opinion(opinion)
    end
  end
end
