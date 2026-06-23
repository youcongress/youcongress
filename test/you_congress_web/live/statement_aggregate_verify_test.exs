defmodule YouCongressWeb.StatementAggregateVerifyTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Votes
  alias YouCongress.VoteVerifications
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

  defp pick_and_save(view, scope, subject, status, comment) do
    view
    |> element(~s|#{scope} button[phx-value-subject="#{subject}"][phx-value-status="#{status}"]|)
    |> render_click()

    view
    |> element(~s|#{scope} input[data-testid="verification-comment-input-#{subject}"]|)
    |> render_keyup(%{"value" => comment})

    view
    |> element(~s|#{scope} button[data-testid="verification-save-#{subject}"]|)
    |> render_click()
  end

  test "an admin can verify quote, relevance and answer from the statement page",
       %{conn: conn, statement: statement, opinion: opinion, vote: vote} do
    conn = log_in_as_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")

    card = ~s|[data-testid="vote-card-#{vote.id}"]|

    btn = fn subject, status ->
      ~s|#{card} button[phx-value-subject="#{subject}"][phx-value-status="#{status}"]|
    end

    # Open the popover.
    view |> element(~s|#{card} button[phx-click="toggle-dropdown"]|) |> render_click()

    # Downstream rows start gated.
    refute has_element?(view, btn.("relevance", "verified"))
    refute has_element?(view, btn.("vote", "verified"))

    # Verify the quote -> relevance unlocks, answer still gated.
    pick_and_save(view, card, "quote", "verified", "Quote is authentic")
    assert has_element?(view, btn.("relevance", "verified"))
    refute has_element?(view, btn.("vote", "verified"))

    # Verify relevance -> answer unlocks.
    pick_and_save(view, card, "relevance", "verified", "Quote matches statement")
    assert has_element?(view, btn.("vote", "verified"))

    # Verify the answer.
    pick_and_save(view, card, "vote", "verified", "Vote answer is correct")

    assert Votes.get_vote!(vote.id).verification_status == :verified

    assert OpinionsStatements.get_opinion_statement(opinion.id, statement.id).verification_status ==
             :verified
  end

  test "the statement page aggregate badge says endorsed when all three rows are endorsed",
       %{conn: conn, statement: statement, vote: vote} do
    conn = log_in_as_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")

    card = ~s|[data-testid="vote-card-#{vote.id}"]|

    view |> element(~s|#{card} button[phx-click="toggle-dropdown"]|) |> render_click()

    pick_and_save(view, card, "quote", "endorsed", "Author endorsed quote")
    pick_and_save(view, card, "relevance", "endorsed", "Author endorsed relevance")
    pick_and_save(view, card, "vote", "endorsed", "Author endorsed vote")

    assert view
           |> element(~s|#{card} button[phx-click="toggle-dropdown"]|)
           |> render() =~ "Endorsed"
  end

  test "answer verification follows the displayed alternate quote", %{conn: conn} do
    statement = statement_fixture()
    author = author_fixture()

    # Displayed first (newer date), but NOT the quote the vote points at.
    shown =
      opinion_fixture(%{
        author_id: author.id,
        content: "Newer quote",
        source_url: "https://example.com/higher",
        date: ~D[2025-01-01],
        date_precision: :year,
        twin: false
      })

    # The vote's own quote (older date) — what the answer is bound to.
    voted =
      opinion_fixture(%{
        author_id: author.id,
        content: "Older quote",
        source_url: "https://example.com/lower",
        date: ~D[2020-01-01],
        date_precision: :year,
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

    # The displayed quote is the newer alternate, so all three verification
    # dimensions are recorded in that quote's context.
    view |> element(~s|#{card} button[phx-click="toggle-dropdown"]|) |> render_click()
    pick_and_save(view, card, "quote", "verified", "Quote is authentic")
    pick_and_save(view, card, "relevance", "verified", "Quote matches statement")
    assert has_element?(view, btn.("vote", "verified"))
    pick_and_save(view, card, "vote", "verified", "Vote answer is correct")

    assert VoteVerifications.status_for_vote_opinion(vote.id, shown.id) == :verified

    # The vote cache only reflects verification of the quote it currently
    # references, so verifying an alternate must not update it.
    assert Votes.get_vote!(vote.id).verification_status == nil
  end
end
