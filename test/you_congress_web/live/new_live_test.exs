defmodule YouCongressWeb.NewLiveTest do
  use YouCongressWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Opinions

  defp add_opinion(statement, author, attrs) do
    opinion = opinion_fixture(Keyword.put(attrs, :author_id, author.id))

    {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

    vote_fixture(
      Map.merge(
        %{statement_id: statement.id, author_id: author.id, opinion_id: opinion.id},
        Map.new(attrs)
      )
    )
  end

  describe "new page" do
    test "renders the feed of newest opinions", %{conn: conn} do
      statement = statement_fixture(title: "AI Safety Statement")
      author = author_fixture(%{name: "Ada Lovelace"})

      add_opinion(statement, author,
        content: "A very recent opinion",
        answer: :for,
        date: ~D[2026-01-01],
        date_precision: :day
      )

      {:ok, _view, html} = live(conn, ~p"/new")

      assert html =~ "Newest Opinions"
      assert html =~ "AI Safety Statement"
      assert html =~ "A very recent opinion"
      assert html =~ "Ada Lovelace"
    end

    test "shows only the newest opinion per statement, not one per answer", %{conn: conn} do
      statement = statement_fixture(title: "One Opinion Statement")
      for_author = author_fixture()
      against_author = author_fixture()
      newest_author = author_fixture()

      add_opinion(statement, for_author,
        content: "Older for opinion",
        answer: :for,
        date: ~D[2024-01-01],
        date_precision: :day
      )

      add_opinion(statement, against_author,
        content: "Older against opinion",
        answer: :against,
        date: ~D[2024-02-01],
        date_precision: :day
      )

      add_opinion(statement, newest_author,
        content: "Newest abstain opinion",
        answer: :abstain,
        date: ~D[2026-01-01],
        date_precision: :day
      )

      {:ok, _view, html} = live(conn, ~p"/new")

      assert html =~ "Newest abstain opinion"
      refute html =~ "Older for opinion"
      refute html =~ "Older against opinion"
    end

    test "orders statements by the date of the opinion", %{conn: conn} do
      older_statement = statement_fixture(title: "Older opinion statement")
      newer_statement = statement_fixture(title: "Newer opinion statement")

      add_opinion(older_statement, author_fixture(),
        content: "Older dated opinion",
        answer: :for,
        date: ~D[2020-01-01],
        date_precision: :day
      )

      add_opinion(newer_statement, author_fixture(),
        content: "Newer dated opinion",
        answer: :for,
        date: ~D[2026-06-18],
        date_precision: :day
      )

      {:ok, _view, html} = live(conn, ~p"/new")

      newer_position = html |> :binary.match("Newer dated opinion") |> elem(0)
      older_position = html |> :binary.match("Older dated opinion") |> elem(0)
      assert newer_position < older_position
    end

    test "shows the author's statements and votes under the opinion", %{conn: conn} do
      author = author_fixture(%{name: "Grace Hopper"})

      featured_statement = statement_fixture(title: "Featured Statement")
      other_statement = statement_fixture(title: "Other Voted Statement")

      add_opinion(featured_statement, author,
        content: "Featured newest opinion",
        answer: :for,
        date: ~D[2026-02-01],
        date_precision: :day
      )

      # A plain vote (without opinion) on another statement: it should be
      # listed under the author's statements and votes.
      vote_fixture(%{
        statement_id: other_statement.id,
        author_id: author.id,
        answer: :against
      })

      {:ok, _view, html} = live(conn, ~p"/new")

      assert html =~ "Grace Hopper · statements &amp; votes"
      assert html =~ "Other Voted Statement"
      assert html =~ "Against"
      assert html =~ "See all of Grace Hopper"

      # Only the card for the statement with an opinion vote is rendered
      assert length(Regex.scan(~r/Featured Statement/, html)) == 1
      assert length(Regex.scan(~r/Other Voted Statement/, html)) == 1
    end
  end
end
