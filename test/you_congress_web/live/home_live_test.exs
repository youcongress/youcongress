defmodule YouCongressWeb.HomeLiveTest do
  use YouCongressWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Halls
  alias YouCongress.HallsStatements.HallStatement
  alias YouCongress.Repo

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

      non_wikipedia_statement =
        statement_fixture(title: "Non-Wikipedia AI Statement")
        |> add_statement_to_ai_hall()
        |> add_opinion_to_statement(%{wikipedia_url: nil})

      {:ok, view, html} = live(conn, ~p"/")

      # Default "New" mode shows both statements
      assert html =~ wikipedia_statement.title
      assert html =~ non_wikipedia_statement.title
    end

    test "shows statements feed in New mode", %{conn: conn} do
      statement =
        statement_fixture(title: "AI Safety Statement")
        |> add_statement_to_ai_hall()
        |> add_opinion_to_statement()

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ statement.title
    end

    test "guest can vote and sees flash message", %{conn: conn} do
      statement_fixture(title: "Test Statement")
      |> add_statement_to_ai_hall()
      |> add_opinion_to_statement()

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
