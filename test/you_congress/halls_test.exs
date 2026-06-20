defmodule YouCongress.HallsTest do
  use YouCongress.DataCase

  alias YouCongress.{Halls, HallsStatements, Opinions}

  import YouCongress.AuthorsFixtures
  import YouCongress.HallsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

  describe "halls" do
    alias YouCongress.Halls.Hall

    @invalid_attrs %{name: nil}

    test "list_halls/0 returns all halls" do
      hall = hall_fixture()
      assert Halls.list_halls() == [hall]
    end

    test "list_halls/1 supports limit" do
      h1 = hall_fixture(name: "alignment")
      h2 = hall_fixture(name: "governance")
      h3 = hall_fixture(name: "safety")

      results = Halls.list_halls(limit: 2)

      assert length(results) == 2
      assert Enum.all?(results, &(&1.id in [h1.id, h2.id, h3.id]))
    end

    test "get_hall!/1 returns the hall with given id" do
      hall = hall_fixture()
      assert Halls.get_hall!(hall.id) == hall
    end

    test "create_hall/1 with valid data creates a hall" do
      valid_attrs = %{name: "some name"}

      assert {:ok, %Hall{} = hall} = Halls.create_hall(valid_attrs)
      assert hall.name == "some name"
    end

    test "create_hall/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Halls.create_hall(@invalid_attrs)
    end

    test "update_hall/2 with valid data updates the hall" do
      hall = hall_fixture()
      update_attrs = %{name: "some updated name"}

      assert {:ok, %Hall{} = hall} = Halls.update_hall(hall, update_attrs)
      assert hall.name == "some updated name"
    end

    test "update_hall/2 with invalid data returns error changeset" do
      hall = hall_fixture()
      assert {:error, %Ecto.Changeset{}} = Halls.update_hall(hall, @invalid_attrs)
      assert hall == Halls.get_hall!(hall.id)
    end

    test "delete_hall/1 deletes the hall" do
      hall = hall_fixture()
      assert {:ok, %Hall{}} = Halls.delete_hall(hall)
      assert_raise Ecto.NoResultsError, fn -> Halls.get_hall!(hall.id) end
    end

    test "change_hall/1 returns a hall changeset" do
      hall = hall_fixture()
      assert %Ecto.Changeset{} = Halls.change_hall(hall)
    end

    test "classify/1 returns fake tags" do
      assert {:ok, %{main_tag: "fake", other_tags: [_], cost: 0}} = Halls.classify("some text")
    end
  end

  describe "hall_stats/1" do
    test "counts and features only positively verified quotes" do
      hall = hall_fixture(%{name: "verified-quotes"})
      statement = statement_fixture()

      assert {:ok, _statement} =
               HallsStatements.sync!(statement.id, %{
                 main_tag: hall.name,
                 other_tags: []
               })

      included_authors = [
        add_quote(statement, "AI Verified Author", :ai_verified),
        add_quote(statement, "Verified Author", :verified),
        add_quote(statement, "Endorsed Author", :endorsed)
      ]

      excluded_authors = [
        add_quote(statement, "Unverified Author", nil),
        add_quote(statement, "Disputed Author", :disputed),
        add_quote(statement, "Unverifiable Author", :unverifiable),
        add_quote(statement, "AI Unverifiable Author", :ai_unverifiable)
      ]

      stats = Halls.hall_stats(hall.name)
      top_author_ids = stats.top_authors |> Enum.map(& &1.id) |> MapSet.new()

      assert stats.quote_count == 3
      assert top_author_ids == included_authors |> Enum.map(& &1.id) |> MapSet.new()

      refute Enum.any?(excluded_authors, &MapSet.member?(top_author_ids, &1.id))
    end
  end

  defp add_quote(statement, author_name, verification_status) do
    author = author_fixture(%{name: author_name})

    quote =
      opinion_fixture(%{
        author_id: author.id,
        verification_status: verification_status
      })

    assert {:ok, quote} = Opinions.update_opinion(quote, %{twin: false})
    assert {:ok, _quote} = Opinions.add_opinion_to_statement(quote, statement.id)

    author
  end
end
