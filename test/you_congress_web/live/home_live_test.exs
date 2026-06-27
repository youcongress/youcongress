defmodule YouCongressWeb.HomeLiveTest do
  use YouCongressWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Halls
  alias YouCongress.HallsStatements.HallStatement
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo
  alias YouCongress.Votes.Vote

  defp add_statement_to_ai_hall(statement) do
    {:ok, hall} = Halls.get_or_create_by_name("ai")

    %HallStatement{}
    |> HallStatement.changeset(%{
      statement_id: statement.id,
      hall_id: hall.id,
      is_main: true
    })
    |> Repo.insert!()

    statement
  end

  defp add_opinion_to_statement(statement, author_attrs \\ %{}) do
    author = author_fixture(author_attrs)
    opinion = opinion_fixture(%{author_id: author.id, content: "Test opinion"})

    _vote =
      vote_fixture(%{statement_id: statement.id, author_id: author.id, opinion_id: opinion.id})

    statement
  end

  describe "Home page for non-logged visitors" do
    test "renders home page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "YouCongress Polls"
      assert html =~ "Search AI quotes, people, policies..."
    end

    test "shows statements regardless of wikipedia metadata in default mode", %{conn: conn} do
      wikipedia_statement =
        statement_fixture(title: "Wikipedia-backed AI Statement")
        |> add_statement_to_ai_hall()
        |> add_opinion_to_statement()

      fill_statement_with_quotes(wikipedia_statement.id)

      non_wikipedia_statement =
        statement_fixture(title: "Non-Wikipedia AI Statement")
        |> add_statement_to_ai_hall()
        |> add_opinion_to_statement(%{wikipedia_url: nil})

      fill_statement_with_quotes(non_wikipedia_statement.id)

      {:ok, _view, html} = live(conn, ~p"/")

      # Default quote-date mode shows both statements
      assert html =~ wikipedia_statement.title
      assert html =~ non_wikipedia_statement.title
    end

    test "shows statements feed in default quote-date mode", %{conn: conn} do
      statement =
        statement_fixture(title: "AI Safety Statement")
        |> add_statement_to_ai_hall()
        |> add_opinion_to_statement()

      fill_statement_with_quotes(statement.id)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ statement.title
    end

    test "defaults to quote date order and toggles to added order", %{conn: conn} do
      newer_date_statement =
        statement_fixture(title: "Newest quote date statement")
        |> add_statement_to_ai_hall()

      fill_statement_with_quotes(newer_date_statement.id, 19)
      newer_date_author = author_fixture()

      newer_date_opinion =
        opinion_fixture(%{
          author_id: newer_date_author.id,
          content: "Newest quote date content",
          verification_status: :ai_verified,
          date: ~D[2026-01-01],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(newer_date_opinion, newer_date_statement.id)

      vote_fixture(%{
        statement_id: newer_date_statement.id,
        author_id: newer_date_author.id,
        opinion_id: newer_date_opinion.id,
        answer: :for
      })

      older_date_statement =
        statement_fixture(title: "Most recently added statement")
        |> add_statement_to_ai_hall()

      fill_statement_with_quotes(older_date_statement.id, 19)
      older_date_author = author_fixture()

      older_date_opinion =
        opinion_fixture(%{
          author_id: older_date_author.id,
          content: "Most recently added content",
          verification_status: :ai_verified,
          date: ~D[2020-01-01],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_date_opinion, older_date_statement.id)

      vote_fixture(%{
        statement_id: older_date_statement.id,
        author_id: older_date_author.id,
        opinion_id: older_date_opinion.id,
        answer: :for
      })

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Quote date"
      assert html =~ "Added"
      assert html =~ "Newest quote date content"
      assert html =~ "Most recently added content"

      newer_date_position = html |> :binary.match(newer_date_statement.title) |> elem(0)
      older_date_position = html |> :binary.match(older_date_statement.title) |> elem(0)
      assert newer_date_position < older_date_position

      view |> element("button[phx-click='toggle-switch']") |> render_click()
      added_html = render(view)

      older_added_position = added_html |> :binary.match(older_date_statement.title) |> elem(0)
      newer_added_position = added_html |> :binary.match(newer_date_statement.title) |> elem(0)
      assert older_added_position < newer_added_position
    end

    test "shows added time inline in default quote-date mode", %{conn: conn} do
      statement =
        statement_fixture(title: "Timestamp Statement")
        |> add_statement_to_ai_hall()

      fill_statement_with_quotes(statement.id)

      author = author_fixture()
      opinion = opinion_fixture(%{author_id: author.id, content: "Timestamped opinion content"})

      vote =
        vote_fixture(%{statement_id: statement.id, author_id: author.id, opinion_id: opinion.id})

      opinion_inserted_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-90 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      vote_inserted_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-13 * 86_400, :second)
        |> NaiveDateTime.truncate(:second)

      from(o in Opinion, where: o.id == ^opinion.id)
      |> Repo.update_all(set: [inserted_at: opinion_inserted_at, updated_at: opinion_inserted_at])

      from(v in Vote, where: v.id == ^vote.id)
      |> Repo.update_all(set: [inserted_at: vote_inserted_at, updated_at: vote_inserted_at])

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Timestamped opinion content"

      refute has_element?(view, "[data-testid='added-at-badge-#{vote.id}']")

      assert has_element?(
               view,
               "[data-testid='added-at-inline-#{vote.id}']",
               "added 1h ago"
             )

      card_html = view |> element("[data-testid='vote-card-#{vote.id}']") |> render()
      assert length(Regex.scan(~r/added 1h ago/, card_html)) == 1
      refute html =~ "13d ago"
    end

    test "uses a gray added badge in added mode for opinions older than one week", %{conn: conn} do
      statement =
        statement_fixture(title: "Older Timestamp Statement")
        |> add_statement_to_ai_hall()

      fill_statement_with_quotes(statement.id)

      author = author_fixture()
      opinion = opinion_fixture(%{author_id: author.id, content: "Older timestamped opinion"})

      vote =
        vote_fixture(%{statement_id: statement.id, author_id: author.id, opinion_id: opinion.id})

      opinion_inserted_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-8 * 86_400, :second)
        |> NaiveDateTime.truncate(:second)

      from(o in Opinion, where: o.id == ^opinion.id)
      |> Repo.update_all(set: [inserted_at: opinion_inserted_at, updated_at: opinion_inserted_at])

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button[phx-click='toggle-switch']") |> render_click()

      assert has_element?(
               view,
               "[data-testid='added-at-badge-#{vote.id}'].bg-gray-100.text-gray-600",
               "Added 8d ago"
             )

      refute has_element?(
               view,
               "[data-testid='added-at-badge-#{vote.id}'].bg-indigo-50"
             )

      refute has_element?(view, "[data-testid='added-at-inline-#{vote.id}']")
    end

    test "lets visitors switch between an author's sourced quotes on the feed", %{conn: conn} do
      statement =
        statement_fixture(title: "Multi quote feed statement")
        |> add_statement_to_ai_hall()

      fill_statement_with_quotes(statement.id, 19)

      author = author_fixture()

      older_opinion =
        opinion_fixture(%{
          author_id: author.id,
          content: "Older feed quote",
          source_url: "https://example.com/feed-older",
          date: ~D[2023-01-01],
          date_precision: :year
        })

      newer_opinion =
        opinion_fixture(%{
          author_id: author.id,
          content: "Newer feed quote",
          source_url: "https://example.com/feed-newer",
          date: ~D[2024-01-01],
          date_precision: :year
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_opinion, statement.id)
      {:ok, _} = Opinions.add_opinion_to_statement(newer_opinion, statement.id)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: newer_opinion.id,
          answer: :for
        })

      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ statement.title
      assert html =~ "Newer feed quote"
      refute html =~ "Older feed quote"
      assert has_element?(view, "[data-testid='quote-position-#{vote.id}']", "1 of 2")

      view
      |> element("[data-testid='vote-card-#{vote.id}'] button[aria-label='Next quote']")
      |> render_click()

      html = render(view)
      assert html =~ "Older feed quote"
      assert has_element?(view, "[data-testid='quote-position-#{vote.id}']", "2 of 2")
    end

    test "shows aggregate verified quotes before quote-only verified or disputed quotes", %{
      conn: conn
    } do
      statement =
        statement_fixture(title: "Verified quote feed statement")
        |> add_statement_to_ai_hall()

      fill_statement_with_quotes(statement.id, 18)

      aggregate_author = author_fixture()

      aggregate_opinion =
        opinion_fixture(%{
          author_id: aggregate_author.id,
          content: "Aggregate verified feed quote",
          verification_status: :ai_verified,
          likes_count: 0
        })

      {:ok, _} = Opinions.add_opinion_to_statement(aggregate_opinion, statement.id)

      aggregate_opinion.id
      |> YouCongress.OpinionsStatements.get_opinion_statement(statement.id)
      |> Ecto.Changeset.change(verification_status: :ai_verified)
      |> YouCongress.Repo.update!()

      vote_fixture(%{
        statement_id: statement.id,
        author_id: aggregate_author.id,
        opinion_id: aggregate_opinion.id,
        answer: :for,
        verification_status: :ai_verified
      })

      quote_only_author = author_fixture()

      quote_only_opinion =
        opinion_fixture(%{
          author_id: quote_only_author.id,
          content: "Newer quote-only verified feed quote",
          verification_status: :verified,
          likes_count: 10
        })

      {:ok, _} = Opinions.add_opinion_to_statement(quote_only_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: quote_only_author.id,
        opinion_id: quote_only_opinion.id,
        answer: :for
      })

      disputed_author = author_fixture()

      disputed_opinion =
        opinion_fixture(%{
          author_id: disputed_author.id,
          content: "Newer disputed feed quote",
          verification_status: :disputed
        })

      {:ok, _} = Opinions.add_opinion_to_statement(disputed_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: disputed_author.id,
        opinion_id: disputed_opinion.id,
        answer: :for
      })

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ statement.title
      assert html =~ "Aggregate verified feed quote"
      refute html =~ "Newer quote-only verified feed quote"
      refute html =~ "Newer disputed feed quote"
    end

    test "renders home feed profile images as square non-shrinking circles", %{conn: conn} do
      statement =
        statement_fixture(title: "Avatar Shape Statement")
        |> add_statement_to_ai_hall()

      fill_statement_with_quotes(statement.id)

      profile_image_url = "https://example.com/portrait.jpg"
      author = author_fixture(%{profile_image_url: profile_image_url})
      opinion = opinion_fixture(%{author_id: author.id, content: "Profile image opinion"})

      vote_fixture(%{
        statement_id: statement.id,
        author_id: author.id,
        opinion_id: opinion.id,
        answer: :for
      })

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ profile_image_url
      assert html =~ "flex items-center space-x-2"
      assert html =~ "shrink-0"
      assert html =~ "relative top-1 inline-flex cursor-pointer"

      assert html =~
               "inline-block h-10 w-10 min-w-[2.5rem] shrink-0 rounded-full object-cover align-middle"
    end

    test "guest can vote and sees flash message", %{conn: conn} do
      statement =
        statement_fixture(title: "Test Statement")
        |> add_statement_to_ai_hall()
        |> add_opinion_to_statement()

      fill_statement_with_quotes(statement.id)

      {:ok, view, _html} = live(conn, ~p"/")

      # Vote For
      view
      |> element("button[id$='-vote-for']")
      |> render_click()

      assert render(view) =~ "For"
    end

    test "search functionality", %{conn: conn} do
      _statement = statement_fixture(title: "AI Safety Bill") |> add_statement_to_ai_hall()
      _other_statement = statement_fixture(title: "Tax Reform") |> add_statement_to_ai_hall()

      {:ok, view, _html} = live(conn, ~p"/")

      # Perform a search
      view
      |> form("form[phx-change=search]", %{"search" => "AI"})
      |> render_change()

      assert render(view) =~ "<b>AI</b> Safety Bill"
      refute render(view) =~ "Tax Reform"
    end
  end

  describe "Home page for logged in users" do
    test "logged in user can vote", %{conn: conn} do
      user = user_fixture()

      statement =
        statement_fixture(title: "Test Statement")
        |> add_statement_to_ai_hall()
        |> add_opinion_to_statement()

      fill_statement_with_quotes(statement.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      # Vote For
      view
      |> element("button[id$='-vote-for']")
      |> render_click()

      assert view |> element("button[id$='-vote-for']") |> render() =~ "For"

      # Verify vote is persisted
      assert YouCongress.Votes.get_current_user_vote(statement.id, user.author_id).answer == :for
    end
  end
end
