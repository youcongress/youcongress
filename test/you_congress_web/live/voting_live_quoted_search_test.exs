defmodule YouCongressWeb.VotingLiveQuotedSearchTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.OpinionsFixtures

  describe "Quoted Search" do
    test "matches exact phrase with quotes", %{conn: conn} do
      opinion = opinion_fixture(content: "The quick brown fox jumps")
      other = opinion_fixture(content: "The fox jumps quickly")

      # Search for "brown fox" (with quotes)
      # "The quick [brown fox] jumps" -> Match
      # "The fox jumps quickly" -> No match
      {:ok, _view, html} = live(conn, ~p"/?search=\"brown fox\"", on_error: :warn)

      assert html =~ "The quick"
      refute html =~ "quickly"
    end

    test "matches any order without quotes", %{conn: conn} do
      opinion = opinion_fixture(content: "The quick brown fox")
      other = opinion_fixture(content: "fox matches brown")

      # Search for brown fox (no quotes) -> both should match
      {:ok, _view, html} = live(conn, ~p"/?search=brown fox", on_error: :warn)

      # Expecting <b>fox</b> matches <b>brown</b>
      assert html =~ "<b>fox</b>"
      assert html =~ "matches"
      assert html =~ "<b>brown</b>"
    end

    test "does NOT match if terms are present but not adjacent when quoted", %{conn: conn} do
      opinion = opinion_fixture(content: "The brown quick fox")

      # Search for "brown fox" -> should NOT match because "quick" is in between
      # But LiveView search logic separates results by tabs. We check if opinion is in list.
      # If no results, tab might default to quotes but show empty.

      {:ok, _view, html} = live(conn, ~p"/?search=\"brown fox\"", on_error: :warn)

      refute html =~ "The brown quick fox"
    end
  end
end
