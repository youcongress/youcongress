defmodule YouCongressWeb.StatementAggregateVerifyTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Votes
  alias YouCongress.OpinionsStatements

  defp setup_quote(_) do
    statement = statement_fixture()
    author = author_fixture()

    opinion =
      opinion_fixture(%{
        author_id: author.id,
        source_url: "https://example.com/quote",
        twin: false
      })

    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion, statement.id)

    vote =
      vote_fixture(%{statement_id: statement.id, author_id: author.id, opinion_id: opinion.id})

    %{statement: statement, author: author, opinion: opinion, vote: vote}
  end

  setup [:setup_quote]

  test "an admin can verify quote, relevance and answer from the statement page",
       %{conn: conn, statement: statement, opinion: opinion, vote: vote} do
    conn = log_in_as_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")

    card = ~s|[data-testid="vote-card-#{vote.id}"]|

    btn = fn subject, status ->
      ~s|#{card} button[phx-value-subject="#{subject}"][phx-value-status="#{status}"]|
    end

    # Open the popover.
    view |> element(~s|#{card} span[phx-click="toggle-dropdown"]|) |> render_click()

    # Downstream rows start gated.
    refute has_element?(view, btn.("relevance", "verified"))
    refute has_element?(view, btn.("vote", "verified"))

    # Verify the quote -> relevance unlocks, answer still gated.
    view |> element(btn.("quote", "verified")) |> render_click()
    assert has_element?(view, btn.("relevance", "verified"))
    refute has_element?(view, btn.("vote", "verified"))

    # Verify relevance -> answer unlocks.
    view |> element(btn.("relevance", "verified")) |> render_click()
    assert has_element?(view, btn.("vote", "verified"))

    # Verify the answer.
    view |> element(btn.("vote", "verified")) |> render_click()

    assert Votes.get_vote!(vote.id).verification_status == :verified

    assert OpinionsStatements.get_opinion_statement(opinion.id, statement.id).verification_status ==
             :verified
  end

  test "answer is verifiable even when an alternate quote is displayed", %{conn: conn} do
    statement = statement_fixture()
    author = author_fixture()

    # Displayed first (higher year), but NOT the quote the vote points at.
    shown =
      opinion_fixture(%{
        author_id: author.id,
        content: "Higher year quote",
        source_url: "https://example.com/higher",
        year: 2025,
        twin: false
      })

    # The vote's own quote (lower year) — what the answer is bound to.
    voted =
      opinion_fixture(%{
        author_id: author.id,
        content: "Lower year quote",
        source_url: "https://example.com/lower",
        year: 2020,
        twin: false
      })

    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(shown, statement.id)
    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(voted, statement.id)

    vote =
      vote_fixture(%{statement_id: statement.id, author_id: author.id, opinion_id: voted.id})

    conn = log_in_as_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")

    card = ~s|[data-testid="vote-card-#{vote.id}"]|
    btn = fn s, st -> ~s|#{card} button[phx-value-subject="#{s}"][phx-value-status="#{st}"]| end

    # The displayed quote is the higher-year alternate, but the answer (bound to
    # the vote's own quote) is still verifiable from here.
    view |> element(~s|#{card} span[phx-click="toggle-dropdown"]|) |> render_click()
    view |> element(btn.("quote", "verified")) |> render_click()
    view |> element(btn.("relevance", "verified")) |> render_click()
    assert has_element?(view, btn.("vote", "verified"))
    view |> element(btn.("vote", "verified")) |> render_click()

    assert Votes.get_vote!(vote.id).verification_status == :verified
  end
end
