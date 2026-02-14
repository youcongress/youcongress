defmodule YouCongressWeb.VerificationLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Verifications

  defp create_verified_opinion(_context) do
    user = user_fixture()
    statement = statement_fixture()
    opinion = opinion_fixture(%{content: "Test quote content", twin: true, source_url: "https://example.com"})

    # Link opinion to statement via a vote
    vote =
      vote_fixture(%{
        statement_id: statement.id,
        author_id: opinion.author_id,
        opinion_id: opinion.id
      })

    # Add opinion-statement association
    YouCongress.Opinions.add_opinion_to_statement(opinion, statement.id)

    # Create a verification
    {:ok, verification} =
      Verifications.create_verification(%{
        opinion_id: opinion.id,
        user_id: user.id,
        status: :verified,
        comment: "Looks accurate"
      })

    %{opinion: opinion, statement: statement, vote: vote, user: user, verification: verification}
  end

  describe "/verifications page" do
    setup [:create_verified_opinion]

    test "renders the verifications feed", %{conn: conn, statement: statement} do
      {:ok, _view, html} = live(conn, ~p"/verifications")

      assert html =~ "Quotes verified recently"
      assert html =~ statement.title
      assert html =~ "Verification History"
      assert html =~ "Looks accurate"
    end

    test "shows the opinion card with statement title", %{conn: conn, statement: statement} do
      {:ok, _view, html} = live(conn, ~p"/verifications")

      assert html =~ statement.title
    end

    test "shows verification history with status badge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/verifications")

      assert html =~ "Verified"
      assert html =~ "Looks accurate"
    end

    test "shows empty state when no verifications", %{conn: conn} do
      # Clean up all verifications
      YouCongress.Repo.delete_all(YouCongress.Verifications.Verification)

      {:ok, _view, html} = live(conn, ~p"/verifications")
      assert html =~ "No verifications yet."
    end

    test "groups multiple verifications under one opinion card", %{
      conn: conn,
      opinion: opinion
    } do
      other_user = user_fixture()

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: other_user.id,
          status: :disputed,
          comment: "I disagree"
        })

      {:ok, _view, html} = live(conn, ~p"/verifications")

      assert html =~ "Looks accurate"
      assert html =~ "I disagree"
      assert html =~ "Disputed"
    end

    test "accessible without login", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/verifications")
    end

    test "renders voting buttons for logged-in user", %{conn: conn} do
      conn = log_in_as_user(conn)
      {:ok, _view, html} = live(conn, ~p"/verifications")

      assert html =~ "For"
      assert html =~ "Against"
      assert html =~ "Abstain"
    end
  end

  describe "/verifications pagination" do
    test "paginates with Load more", %{conn: conn} do
      statement = statement_fixture()
      user = user_fixture()

      # Create 25 opinions with verifications
      Enum.each(1..25, fn i ->
        opinion =
          opinion_fixture(%{content: "Paginated opinion #{i}", twin: true, source_url: "https://example.com/#{i}"})

        vote_fixture(%{statement_id: statement.id, author_id: opinion.author_id, opinion_id: opinion.id})
        YouCongress.Opinions.add_opinion_to_statement(opinion, statement.id)

        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Verified #{i}"
        })
      end)

      {:ok, view, html} = live(conn, ~p"/verifications")
      assert html =~ "Load more"

      view
      |> element("button", "Load more")
      |> render_click()

      html = render(view)
      # After loading more, should have all 25 opinions
      refute html =~ "Load more"
    end
  end
end
