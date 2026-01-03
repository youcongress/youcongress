defmodule YouCongressWeb.HomeLiveTest do
  use YouCongressWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.AccountsFixtures

  describe "Home page" do
    test "renders home page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Verifiable quotes"
      assert html =~ "liquid democracy"
      assert html =~ "Choose your"
    end

    test "search functionality", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Perform a search
      view
      |> form("form[phx-submit=search]", %{"search" => "AI"})
      |> render_submit()

      assert render(view) =~ "Search quotes, people, motions..."
    end
  end

  describe "Delegate selection" do
    setup do
      author1 = author_fixture(name: "Stuart J. Russell")
      author2 = author_fixture(name: "Demis Hassabis")
      statement = statement_fixture(title: "AI Safety Statement")

      # Create opinions/votes for these authors so they are relevant to the statement
      opinion1 = opinion_fixture(author_id: author1.id, statement_id: statement.id)
      # Manually link opinion to statement as required by list_statements_with_opinions_by_authors
      user = user_fixture()
      {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion1, statement, user.id)

      vote_fixture(
        author_id: author1.id,
        statement_id: statement.id,
        opinion_id: opinion1.id,
        answer: :for
      )

      %{author1: author1, author2: author2, statement: statement}
    end

    test "can toggle delegates", %{conn: conn, author1: author1} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ author1.name

      # Select a delegate
      assert has_element?(view, "#delegate-#{author1.id}")

      view
      |> element("input[phx-click='toggle-delegate'][phx-value-id='#{author1.id}']")
      |> render_click()

      # Verify that the state updated (checkbox should be checked)
      # We target the specific checkbox to be sure
      assert has_element?(view, "#delegate-#{author1.id}[checked]")

      # When a delegate is selected, proper statements should appear
      assert render(view) =~ "AI Safety Statement"
    end
  end

  describe "Statement interaction" do
    setup do
      user = user_fixture()
      # Explicitly create author with highlighted delegate name
      author = author_fixture(name: "Yoshua Bengio")

      statement = statement_fixture(title: "Important Motion")
      opinion = opinion_fixture(author_id: author.id, statement_id: statement.id)

      # Link opinion to statement
      {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion, statement, user.id)

      vote_fixture(
        author_id: author.id,
        statement_id: statement.id,
        opinion_id: opinion.id,
        answer: :for
      )

      %{user: user, statement: statement, author: author}
    end

    test "guest cannot vote but sees flash message", %{
      conn: conn,
      statement: statement,
      author: author
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      # First we need to select a delegate to see the voting card in the "selection" list
      assert has_element?(view, "#delegate-#{author.id}")

      view
      |> element("input[phx-click='toggle-delegate'][phx-value-id='#{author.id}']")
      |> render_click()

      # Now try to vote
      view
      |> element("button[phx-value-id='#{statement.id}'][phx-value-answer='for']")
      |> render_click()

      assert render(view) =~ "Please sign up to save your vote."
    end

    test "logged in user can vote", %{
      conn: conn,
      statement: statement,
      user: user,
      author: author
    } do
      conn = log_in_user(conn, user)
      # Check /landing for logged in user if / redirects
      {:ok, view, _html} = live(conn, ~p"/landing")

      # Select delegate to see voting
      assert has_element?(view, "#delegate-#{author.id}")

      view
      |> element("input[phx-click='toggle-delegate'][phx-value-id='#{author.id}']")
      |> render_click()

      # Vote For
      assert has_element?(view, "button[phx-value-id='#{statement.id}'][phx-value-answer='for']")

      view
      |> element("button[phx-value-id='#{statement.id}'][phx-value-answer='for']")
      |> render_click()

      assert render(view) =~ "Voted For"

      # Verify vote is persisted
      assert YouCongress.Votes.get_current_user_vote(statement.id, user.author_id).answer == :for
    end

    test "logged in user can delete vote", %{
      conn: conn,
      statement: statement,
      user: user,
      author: author
    } do
      conn = log_in_user(conn, user)

      # Pre-cast a vote
      vote_fixture(
        author_id: user.author_id,
        statement_id: statement.id,
        answer: :for,
        direct: true
      )

      {:ok, view, _html} = live(conn, ~p"/landing")

      # Select delegate to see voting
      assert has_element?(view, "#delegate-#{author.id}")

      view
      |> element("input[phx-click='toggle-delegate'][phx-value-id='#{author.id}']")
      |> render_click()

      assert render(view) =~ "You&#39;re directly voting"

      # Click remove vote
      view
      |> element("button[phx-click='delete-vote'][phx-value-id='#{statement.id}']")
      |> render_click()

      refute render(view) =~ "You're directly voting"
      refute YouCongress.Votes.get_current_user_vote(statement.id, user.author_id)
    end

    test "guest can select delegate, vote, and register preserving choices", %{
      conn: conn,
      statement: statement,
      author: author
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      # 1. Select Delegate
      view
      |> element("input[phx-click='toggle-delegate'][phx-value-id='#{author.id}']")
      |> render_click()

      # 2. Vote
      view
      |> element("button[phx-value-id='#{statement.id}'][phx-value-answer='for']")
      |> render_click()

      assert render(view) =~ "Please sign up to save your vote"

      # Debugging
      # IO.inspect(Phoenix.LiveViewTest.children(view), label: "View Children")
      # IO.inspect(render(view), label: "HTML with Form")

      # 3. Register using the embedded form
      # Trigger change to validate (optional but realistic)
      assert has_element?(view, "#registration_form")

      child = find_live_child(view, "register-form")

      child
      |> element("#registration_form")
      |> render_submit(%{
        "user" => %{
          "name" => "New User",
          "email" => "new@example.com",
          "password" => "password1234"
        }
      })

      # 4. Verify User Created
      user = YouCongress.Accounts.get_user_by_email("new@example.com")
      assert user

      # 5. Verify Delegation Saved
      assert YouCongress.Delegations.get_delegation(user, author.id)

      # 6. Verify Vote Saved
      assert YouCongress.Votes.get_current_user_vote(statement.id, user.author_id)
    end
  end
end
