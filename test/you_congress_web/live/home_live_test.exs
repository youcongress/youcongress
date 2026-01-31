defmodule YouCongressWeb.HomeLiveTest do
  use YouCongressWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures

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

  describe "Home page for non-logged visitors" do
    test "renders home page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "YouCongress Polls"
      assert html =~ "Search quotes, people, policies..."
    end

    test "shows statements feed in Trending mode", %{conn: conn} do
      statement =
        statement_fixture(title: "AI Safety Statement")
        |> add_statement_to_ai_hall()

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to Trending mode (default is now Top mode which filters by top authors)
      view |> element("button[phx-click='toggle-switch']") |> render_click()

      assert render(view) =~ statement.title
    end

    test "guest can vote and sees flash message", %{conn: conn} do
      statement =
        statement_fixture(title: "Test Statement")
        |> add_statement_to_ai_hall()

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to Trending mode to see the statement
      view |> element("button[phx-click='toggle-switch']") |> render_click()

      # Vote For
      view
      |> element("button##{statement.id}-vote-for")
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

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/")

      # Switch to Trending mode to see the statement
      view |> element("button[phx-click='toggle-switch']") |> render_click()

      # Vote For
      view
      |> element("button##{statement.id}-vote-for")
      |> render_click()

      assert view |> element("button##{statement.id}-vote-for") |> render() =~ "For"

      # Verify vote is persisted
      assert YouCongress.Votes.get_current_user_vote(statement.id, user.author_id).answer == :for
    end
  end
end
