defmodule YouCongressWeb.StatementLiveTest do
  use YouCongressWeb.ConnCase

  import Mock

  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.AuthorsFixtures

  alias YouCongress.Statements
  alias YouCongress.HallsStatements

  @create_attrs %{title: "nuclear energy"}
  @suggested_titles [
    "Should we increase investment in nuclear energy research?",
    "Shall we consider nuclear energy as a viable alternative to fossil fuels?",
    "Could nuclear energy be a key solution for reducing global carbon emissions?"
  ]
  @update_attrs %{title: "some updated title"}
  @invalid_attrs %{title: nil}

  defp create_statement(_) do
    statement = statement_fixture()
    {:ok, _} = HallsStatements.sync!(statement.id, ["ai-safety"])

    %{statement: statement}
  end

  describe "Index" do
    setup [:create_statement]

    test "vote and create opinion", %{conn: conn, statement: statement} do
      conn = log_in_as_user(conn)
      {:ok, index_live, html} = live(conn, ~p"/home")

      assert html =~ statement.title

      # Vote For
      index_live
      |> element("button##{statement.id}-vote-for")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted For"

      # Vote Against
      index_live
      |> element("button##{statement.id}-vote-against")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted Against"

      # Vote Abstain
      index_live
      |> element("button##{statement.id}-vote-abstain")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted Abstain"

      # Create a comment
      index_live
      |> form("#v#{statement.id}-opinion-form", %{"opinion[content]" => "some comment"})
      |> render_submit()

      html = render(index_live)
      assert html =~ "Opinion created successfully"
      assert html =~ "some comment"

      index_live
      |> form("#v#{statement.id}-opinion-form", %{"opinion[content]" => "some updated comment"})
      |> render_submit()

      html = render(index_live)
      assert html =~ "Opinion updated successfully"
      assert html =~ "some updated comment"
    end

    test "saves new statement and redirect to show", %{conn: conn} do
      with_mocks([
        {YouCongress.Statements.TitleRewording, [],
         [generate_rewordings: fn _, _ -> {:ok, @suggested_titles, 0} end]}
      ]) do
        conn = log_in_as_admin(conn)
        {:ok, index_live, _html} = live(conn, ~p"/home")

        index_live
        |> element("button#create-poll-button", "New")
        |> render_click()

        assert index_live
               |> form("#statement-form", statement: @invalid_attrs)
               |> render_change() =~ "can&#39;t be blank"

        [title1, title2, _title3] = @suggested_titles

        assert index_live
               |> form("#statement-form", statement: @create_attrs)
               |> render_submit() =~ title1

        response =
          index_live
          |> element("button", title2)
          |> render_click()

        statement = Statements.get_statement!(title: title2)
        statement_path = ~p"/p/#{statement.slug}"

        {_, {:redirect, %{to: ^statement_path}}} = response
      end
    end
  end

  describe "Show" do
    setup [:create_statement]

    test "displays statement as logged user", %{conn: conn, statement: statement} do
      conn = log_in_as_user(conn)

      {:ok, _show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ statement.title
    end

    test "displays statement as non-logged visitor", %{conn: conn, statement: statement} do
      {:ok, _show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ statement.title
    end

    test "updates statement within modal", %{conn: conn, statement: statement} do
      conn = log_in_as_admin(conn)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      assert show_live
             |> element("a", "Edit")
             |> render_click() =~ "Edit Poll"

      assert_patch(show_live, ~p"/p/#{statement.slug}/show/edit")

      assert show_live
             |> form("#statement-form", statement: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#statement-form", statement: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/p/#{statement.slug}")

      html = render(show_live)
      assert html =~ "Statement updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes statement in listing", %{conn: conn, statement: statement} do
      conn = log_in_as_admin(conn)

      {:ok, index_live, _html} = live(conn, ~p"/p/#{statement.slug}/edit")

      index_live
      |> element("a", "Delete")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn ->
        Statements.get_statement!(statement.id)
      end
    end

    test "casts a vote from statement buttons", %{conn: conn, statement: statement} do
      conn = log_in_as_user(conn)

      opinion = opinion_fixture(%{statement_id: statement.id})
      # Create a vote so we display the voting options
      vote_fixture(%{statement_id: statement.id, opinion_id: opinion.id})

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      # Vote For
      show_live
      |> element("button##{statement.id}-vote-for")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted For"

      # Vote Against
      show_live
      |> element("button##{statement.id}-vote-against")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Against"

      # Vote Abstain
      show_live
      |> element("button##{statement.id}-vote-abstain")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Abstain"
    end

    test "creates a comment", %{conn: conn, statement: statement} do
      conn = log_in_as_user(conn)

      another_user = user_fixture()

      opinion = opinion_fixture(%{statement_id: statement.id})

      #  Create an AI generated comment as we don't display the form until we have one of these
      vote_fixture(%{
        twin: true,
        statement_id: statement.id,
        author_id: another_user.author_id,
        opinion_id: opinion.id
      })

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Comment created successfully"
      assert html =~ "some comment"

      # Check that the vote is Abstain
      assert html =~ "Abstain"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end

    test "edit a comment", %{conn: conn, statement: statement} do
      user = user_fixture()

      conn = log_in_user(conn, user)

      opinion =
        opinion_fixture(%{
          author_id: user.author_id,
          user_id: user.id,
          statement_id: statement.id,
          content: "whatever",
          twin: false
        })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: user.author_id,
        opinion_id: opinion.id,
        user_id: user.id,
        twin: false
      })

      #  Create an AI generated comment as we don't display the form until we have one of these
      vote_fixture(%{twin: true, statement_id: statement.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      assert render(show_live) =~ "whatever"

      show_live
      |> element("a", "Edit comment")
      |> render_click()

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Your comment has been updated"
      refute html =~ "whatever"
      assert html =~ "some comment"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end

    test "like icon click changes from heart.svg to filled-heart.svg", %{conn: conn} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)
      statement = statement_fixture()
      vote_fixture(%{statement_id: statement.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      # We have a heart icon
      assert has_element?(show_live, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(show_live, "img[src='/images/filled-heart.svg']")

      # Like the opinion
      show_live
      |> element("img[src='/images/heart.svg']")
      |> render_click()

      # We have a filled heart icon
      assert has_element?(show_live, "img[src='/images/filled-heart.svg']")

      # We don't have a heart icon
      refute has_element?(show_live, "img[src='/images/heart.svg']")

      # Unlike the opinion
      show_live
      |> element("img[src='/images/filled-heart.svg']")
      |> render_click()

      # We have a heart icon
      assert has_element?(show_live, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(show_live, "img[src='/images/filled-heart.svg']")
    end

    test "filters opinions correctly", %{conn: conn, statement: statement} do
      # Create test data
      user = user_fixture()
      ai_author = author_fixture(%{twin: true})
      ai_author_2 = author_fixture(%{twin: true})
      human_author = author_fixture(%{twin: false})

      # Two quote opinions (with source_url) and one user opinion (no source_url)
      _for_quote =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: ai_author.id,
            answer: :for,
            twin: true
          },
          true
        )

      _against_quote =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: ai_author_2.id,
            answer: :against,
            twin: true
          },
          true
        )

      user_opinion = opinion_fixture(%{author_id: human_author.id, source_url: nil, twin: false})

      abstain_opinion =
        opinion_fixture(%{author_id: user.author_id, source_url: nil, twin: false})

      _abstain_user =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: user.author_id,
            answer: :abstain,
            opinion_id: abstain_opinion.id
          },
          false
        )

      _for_user =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: human_author.id,
            answer: :for,
            twin: false,
            opinion_id: user_opinion.id
          },
          false
        )

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      # Test initial state shows filter buttons
      assert html =~ "Quotes (2)"
      assert html =~ "Users (2)"

      # Test Quotes filter
      html =
        show_live
        |> element("span", "Quotes")
        |> render_click()

      assert html =~ ai_author.name
      refute html =~ human_author.name

      # Test Users filter
      html =
        show_live
        |> element("span", "Users")
        |> render_click()

      assert html =~ human_author.name
      refute html =~ ai_author.name
    end
  end
end
