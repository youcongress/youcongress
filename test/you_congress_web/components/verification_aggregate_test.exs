defmodule YouCongressWeb.Components.VerificationAggregateTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YouCongressWeb.Components.VerificationAggregate
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes.Vote
  alias YouCongress.Accounts.User

  defp moderator, do: %User{id: 1, role: "moderator", author_id: 99}

  defp render_badge(assigns) do
    defaults = %{
      id: "agg-test",
      opinion: %Opinion{id: 1, author_id: 2, verification_status: nil},
      opinion_statement: %OpinionStatement{id: 5, verification_status: nil},
      vote: %Vote{id: 9, opinion_id: 1, verification_status: nil},
      current_user: moderator(),
      show_dropdown: true
    }

    render_component(VerificationAggregate, Map.merge(defaults, assigns))
  end

  test "shows Unverified when nothing is verified" do
    html = render_badge(%{})
    assert html =~ "Unverified"
    # Quote row is always actionable; downstream rows point at the next step.
    assert html =~ "Quote"
    assert html =~ "Relevance"
    assert html =~ "Answer"
    assert html =~ "verify quote first"
    refute html =~ "verify relevance first"
  end

  test "names the actual blocker on each disabled row" do
    # Quote verified, but the quote isn't linked to a statement.
    html =
      render_badge(%{
        opinion: %Opinion{id: 1, author_id: 2, verification_status: :verified},
        opinion_statement: nil
      })

    assert html =~ "not linked to statement"
  end

  test "unlocks the relevance row once the quote is verified" do
    html = render_badge(%{opinion: %Opinion{id: 1, author_id: 2, verification_status: :verified}})
    refute html =~ "verify quote first"
    assert html =~ "verify relevance first"
  end

  test "unlocks the vote row once quote and relevance are verified" do
    html =
      render_badge(%{
        opinion: %Opinion{id: 1, author_id: 2, verification_status: :verified},
        opinion_statement: %OpinionStatement{id: 5, verification_status: :verified}
      })

    refute html =~ "verify quote first"
    refute html =~ "verify relevance first"
  end

  test "shows Verified only when all three are positive" do
    html =
      render_badge(%{
        opinion: %Opinion{id: 1, author_id: 2, verification_status: :verified},
        opinion_statement: %OpinionStatement{id: 5, verification_status: :verified},
        vote: %Vote{id: 9, opinion_id: 1, verification_status: :verified}
      })

    assert html =~ "Verified"
  end

  test "disputed anywhere shows Disputed" do
    html =
      render_badge(%{
        opinion_statement: %OpinionStatement{id: 5, verification_status: :disputed}
      })

    assert html =~ "Disputed"
  end

  test "non-permitted users get a static FAQ link, no popover" do
    html =
      render_badge(%{
        current_user: %User{id: 2, role: "user", author_id: nil},
        show_dropdown: true
      })

    assert html =~ "/faq#verify-quotes"
    refute html =~ "verify quote first"
  end
end
