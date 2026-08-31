defmodule YouCongressWeb.LatestLiveTest do
  use YouCongressWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  import YouCongressWeb.ConnCase

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo

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

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Latest Expert and Citizen Positions"
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

      {:ok, _view, html} = live(conn, ~p"/")

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

      {:ok, _view, html} = live(conn, ~p"/")

      newer_position = html |> :binary.match("Newer dated opinion") |> elem(0)
      older_position = html |> :binary.match("Older dated opinion") |> elem(0)
      assert newer_position < older_position
    end

    test "groups the cards under date headers", %{conn: conn} do
      today_statement = statement_fixture(title: "Today statement")
      old_statement = statement_fixture(title: "Old statement")

      add_opinion(today_statement, author_fixture(),
        content: "Fresh opinion",
        answer: :for,
        date: Date.utc_today(),
        date_precision: :day
      )

      add_opinion(old_statement, author_fixture(),
        content: "Ancient opinion",
        answer: :for,
        date: ~D[1963-08-28],
        date_precision: :day
      )

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(id="latest-date-group-0")
      assert html =~ ~s(id="latest-date-group-1")
      assert html =~ "Today"
      assert html =~ "1963"

      today_position = html |> :binary.match("Today") |> elem(0)
      old_position = html |> :binary.match("1963") |> elem(0)
      assert today_position < old_position
    end

    test "toggles from quote dates to added dates and shows added timestamps", %{conn: conn} do
      recently_added_statement = statement_fixture(title: "Recently added old quote")
      earlier_added_statement = statement_fixture(title: "Earlier added new quote")

      recent_opinion =
        add_opinion(recently_added_statement, author_fixture(),
          content: "Old quote added recently",
          answer: :for,
          date: ~D[2020-01-01],
          date_precision: :day
        )

      earlier_opinion =
        add_opinion(earlier_added_statement, author_fixture(),
          content: "New quote added earlier",
          answer: :against,
          date: Date.utc_today(),
          date_precision: :day
        )

      one_hour_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      eight_days_ago =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-8 * 86_400, :second)
        |> NaiveDateTime.truncate(:second)

      from(o in Opinion, where: o.id == ^recent_opinion.opinion_id)
      |> Repo.update_all(set: [inserted_at: one_hour_ago])

      from(o in Opinion, where: o.id == ^earlier_opinion.opinion_id)
      |> Repo.update_all(set: [inserted_at: eight_days_ago])

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Quote date"
      assert html =~ "Added"
      refute html =~ "Added 1h ago"

      recent_position = html |> :binary.match("Earlier added new quote") |> elem(0)
      old_position = html |> :binary.match("Recently added old quote") |> elem(0)
      assert recent_position < old_position

      view |> element("button[phx-click='toggle-switch']") |> render_click()
      assert_patch(view, "/?sort=quote-added")
      added_html = render(view)

      recently_added_position =
        added_html |> :binary.match("Recently added old quote") |> elem(0)

      earlier_added_position = added_html |> :binary.match("Earlier added new quote") |> elem(0)
      assert recently_added_position < earlier_added_position
      assert added_html =~ "Today"
      assert added_html =~ "Added 1h ago"
      assert added_html =~ "Added 8d ago"

      {:ok, direct_view, direct_html} = live(conn, ~p"/?sort=quote-added")

      assert has_element?(direct_view, "button[role='switch'][aria-checked='true']")
      assert direct_html =~ "Added 1h ago"

      direct_view |> element("button[phx-click='toggle-switch']") |> render_click()
      assert_patch(direct_view, "/")
      refute render(direct_view) =~ "Added 1h ago"
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

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Grace Hopper · statements &amp; votes"
      assert html =~ "Other Voted Statement"
      assert html =~ "Against"
      assert html =~ "See all of Grace Hopper"

      # Only the card for the statement with an opinion vote is rendered
      assert length(Regex.scan(~r/Featured Statement/, html)) == 1
      assert length(Regex.scan(~r/Other Voted Statement/, html)) == 1
    end

    test "hides the like, comment, x and delegate actions for logged out users", %{conn: conn} do
      statement = statement_fixture(title: "Guest Actions Statement")
      author = author_fixture()

      add_opinion(statement, author,
        content: "Guest actions opinion",
        answer: :for,
        date: ~D[2026-01-01],
        date_precision: :day
      )

      {:ok, _view, html} = live(conn, ~p"/")

      refute html =~ "/images/comment.svg"
      refute html =~ "/images/heart.svg"
      refute html =~ "/images/x.svg"
      refute html =~ "Delegate"
    end

    test "shows the like, comment, x and delegate actions for logged in users", %{conn: conn} do
      statement = statement_fixture(title: "Logged In Actions Statement")
      author = author_fixture()

      add_opinion(statement, author,
        content: "Logged in actions opinion",
        answer: :for,
        date: ~D[2026-01-01],
        date_precision: :day
      )

      conn = log_in_user(conn, user_fixture())
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "/images/comment.svg"
      assert html =~ "/images/heart.svg"
      assert html =~ "/images/x.svg"
      assert html =~ "Delegate"
    end
  end
end
