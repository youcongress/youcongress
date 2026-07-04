defmodule YouCongressWeb.StatementLiveSynthesisTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.HallsStatements
  alias YouCongress.Opinions
  alias YouCongress.Statements

  defp enable_synthesis_flag do
    original = Application.fetch_env(:you_congress, :feature_flags)

    flags =
      case original do
        {:ok, map} when is_map(map) -> Map.put(map, :quote_synthesis, true)
        _ -> %{quote_synthesis: true}
      end

    Application.put_env(:you_congress, :feature_flags, flags)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:you_congress, :feature_flags, value)
        :error -> Application.delete_env(:you_congress, :feature_flags)
      end
    end)
  end

  defp statement_with_quotes(count) do
    statement = statement_fixture()
    fill_statement_with_quotes(statement.id, count)
    statement
  end

  defp cited_opinions(statement, count) do
    Opinions.list_opinions(
      statement_ids: [statement.id],
      only_quotes: true,
      limit: count,
      preload: [:author]
    )
  end

  defp put_synthesis(statement, for_ids, against_ids) do
    {:ok, statement} =
      Statements.update_synthesis(statement, %{
        synthesis: %{
          "headline" => "Synthesis headline about the debate.",
          "arguments_for" => [
            %{
              "title" => "Pro cluster title",
              "summary" => "Pro cluster summary.",
              "opinion_ids" => for_ids
            }
          ],
          "arguments_against" => [
            %{
              "title" => "Con cluster title",
              "summary" => "Con cluster summary.",
              "opinion_ids" => against_ids
            }
          ],
          "middle_ground" => [],
          "insights" => ["Insight number one."],
          "conclusion" => "Balanced conclusion text."
        },
        synthesis_generated_at: ~U[2026-07-04 10:00:00Z],
        synthesis_quotes_count: 25
      })

    statement
  end

  defp index_of!(html, text) do
    case :binary.match(html, text) do
      {index, _length} -> index
      :nomatch -> flunk("Expected HTML to include #{inspect(text)}")
    end
  end

  describe "synthesis card" do
    test "renders collapsed with headline and crawlable body", %{conn: conn} do
      statement = statement_with_quotes(25)
      [o1, o2] = cited_opinions(statement, 2)
      statement = put_synthesis(statement, [o1.id], [o2.id])
      enable_synthesis_flag()

      {:ok, view, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "AI synthesis"
      assert html =~ "Synthesis headline about the debate."
      assert html =~ "Show more"
      assert html =~ "Show arguments and insights"
      refute html =~ "AI synthesis of 25 quotes"
      refute html =~ "For 25 · Abstain 0 · Against 0"
      # The body ships in the initial HTML (crawlable) but starts hidden.
      assert html =~ "Pro cluster title"
      assert html =~ "Con cluster title"
      assert html =~ o1.author.name
      assert html =~ "/c/#{o1.id}"
      assert html =~ "Insight number one."
      assert html =~ "Balanced conclusion text."
      assert html =~ "AI-generated from the quotes on this page on Jul 04, 2026"
      assert has_element?(view, "#synthesis-body.hidden")
    end

    test "renders after halls and before voting controls", %{conn: conn} do
      statement = statement_with_quotes(25)
      [o1] = cited_opinions(statement, 1)
      statement = put_synthesis(statement, [o1.id], [])
      {:ok, _statement} = HallsStatements.sync!(statement.id, %{main_tag: "ai", other_tags: []})
      enable_synthesis_flag()

      {:ok, _view, html} = live(conn, ~p"/p/#{statement.slug}")

      hall_index = index_of!(html, ~s(href="/h/ai"))
      synthesis_index = index_of!(html, "AI synthesis")
      vote_index = index_of!(html, "Cast your vote:")

      assert hall_index < synthesis_index
      assert synthesis_index < vote_index
    end

    test "expands and collapses on toggle", %{conn: conn} do
      statement = statement_with_quotes(25)
      [o1] = cited_opinions(statement, 1)
      statement = put_synthesis(statement, [o1.id], [])
      enable_synthesis_flag()

      {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")

      view |> element("button[phx-click='toggle-synthesis']") |> render_click()
      assert_patch(view, ~p"/p/#{statement.slug}?#{%{synthesis: "true"}}")
      assert has_element?(view, "#synthesis-body")
      refute has_element?(view, "#synthesis-body.hidden")
      assert render(view) =~ "Hide"
      refute render(view) =~ "Show arguments and insights"

      view |> element("button[phx-click='toggle-synthesis']") |> render_click()
      assert_patch(view, ~p"/p/#{statement.slug}")
      assert has_element?(view, "#synthesis-body.hidden")
      assert render(view) =~ "Show more"
      assert render(view) =~ "Show arguments and insights"
    end

    test "opens expanded from the synthesis URL param", %{conn: conn} do
      statement = statement_with_quotes(25)
      [o1] = cited_opinions(statement, 1)
      statement = put_synthesis(statement, [o1.id], [])
      enable_synthesis_flag()

      {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}?#{%{synthesis: "true"}}")

      assert has_element?(view, "#synthesis-body")
      refute has_element?(view, "#synthesis-body.hidden")
    end

    test "hidden when the feature flag is off", %{conn: conn} do
      statement = statement_with_quotes(25)
      [o1] = cited_opinions(statement, 1)
      statement = put_synthesis(statement, [o1.id], [])

      {:ok, _view, html} = live(conn, ~p"/p/#{statement.slug}")

      refute html =~ "AI synthesis"
      refute html =~ "Synthesis headline about the debate."
    end

    test "hidden when the statement has no synthesis", %{conn: conn} do
      statement = statement_with_quotes(25)
      enable_synthesis_flag()

      {:ok, _view, html} = live(conn, ~p"/p/#{statement.slug}")

      refute html =~ "AI synthesis"
    end

    test "hidden below the quote floor", %{conn: conn} do
      statement = statement_with_quotes(24)
      [o1] = cited_opinions(statement, 1)
      statement = put_synthesis(statement, [o1.id], [])
      enable_synthesis_flag()

      {:ok, _view, html} = live(conn, ~p"/p/#{statement.slug}")

      refute html =~ "AI synthesis"
    end

    test "omits quotes that were deleted after generation", %{conn: conn} do
      statement = statement_with_quotes(26)
      [o1, o2] = cited_opinions(statement, 2)
      statement = put_synthesis(statement, [o1.id], [o2.id])
      {1, nil} = Opinions.delete_opinion_and_descendants(o1)
      enable_synthesis_flag()

      {:ok, _view, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "AI synthesis"
      refute html =~ "AI synthesis of 25 quotes"
      # The cluster survives; the deleted quote silently disappears from it.
      assert html =~ "Pro cluster title"
      refute html =~ "/c/#{o1.id}"
      assert html =~ "/c/#{o2.id}"
    end

    test "regenerate is hidden for anonymous visitors and regular users", %{conn: conn} do
      statement = statement_with_quotes(25)
      [o1] = cited_opinions(statement, 1)
      statement = put_synthesis(statement, [o1.id], [])
      enable_synthesis_flag()

      {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")
      refute has_element?(view, "button[phx-click='regenerate-synthesis']")

      conn = log_in_as_user(conn)
      {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")
      refute has_element?(view, "button[phx-click='regenerate-synthesis']")
    end

    test "admins can regenerate through the fake pipeline", %{conn: conn} do
      statement = statement_with_quotes(25)
      [o1] = cited_opinions(statement, 1)
      statement = put_synthesis(statement, [o1.id], [])
      enable_synthesis_flag()

      conn = log_in_as_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/p/#{statement.slug}")

      assert has_element?(view, "button[phx-click='regenerate-synthesis']")

      # Oban runs inline in tests, so the click submits, polls and persists.
      view |> element("button[phx-click='regenerate-synthesis']") |> render_click()

      assert render(view) =~ "Regenerating the AI synthesis"

      statement = Statements.get_statement!(statement.id)
      assert statement.synthesis["headline"] =~ "Fake synthesis"
    end
  end
end
