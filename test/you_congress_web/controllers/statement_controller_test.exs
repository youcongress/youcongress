defmodule YouCongressWeb.StatementControllerTest do
  use YouCongressWeb.ConnCase, async: true

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

  alias NimbleCSV.RFC4180, as: CSV
  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.Verifications
  alias YouCongress.Votes
  alias YouCongress.VoteVerifications

  describe "GET /p/:slug/quotes.csv" do
    test "downloads the statement quotes with their latest verifications", %{conn: conn} do
      statement = statement_fixture()

      author =
        author_fixture(%{
          name: "Jane Doe",
          bio: "Physicist",
          twitter_username: "janedoe",
          wikipedia_url: "https://en.wikipedia.org/wiki/Jane_Doe"
        })

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          content: ~s(A quote with "quotes", commas, and\na newline),
          source_url: "https://example.com/article",
          date: ~D[2023-05-10],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      {:ok, vote} =
        Votes.create_vote(%{
          author_id: author.id,
          statement_id: statement.id,
          opinion_id: opinion.id,
          answer: :against
        })

      user = user_fixture()

      # Two quote verifications: only the latest one must be exported.
      {:ok, _old} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :unverifiable,
          comment: "old quote comment"
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "source checked"
        })

      opinion_statement = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)

      {:ok, _} =
        OpinionStatementVerifications.create_verification(%{
          opinion_statement_id: opinion_statement.id,
          user_id: user.id,
          status: :ai_verified,
          comment: "on topic"
        })

      {:ok, _} =
        VoteVerifications.create_verification(%{
          vote_id: vote.id,
          user_id: user.id,
          status: :disputed,
          comment: "answer looks wrong"
        })

      conn = get(conn, ~p"/p/#{statement.slug}/quotes.csv")

      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="#{statement.slug}-quotes.csv")
             ]

      body = response(conn, 200)
      [row] = CSV.parse_string(body)

      assert [headers, ^row] = CSV.parse_string(body, skip_headers: false)

      assert headers == [
               "opinion_id",
               "author",
               "author_bio",
               "author_x_url",
               "author_wikipedia_url",
               "quote",
               "vote",
               "quote_date",
               "quote_date_precision",
               "source_url",
               "quote_verification_status",
               "quote_verification_comment",
               "quote_verification_date",
               "relevance_verification_status",
               "relevance_verification_comment",
               "relevance_verification_date",
               "vote_verification_status",
               "vote_verification_comment",
               "vote_verification_date"
             ]

      today = Date.utc_today() |> Date.to_iso8601()

      assert row == [
               to_string(opinion.id),
               "Jane Doe",
               "Physicist",
               "https://x.com/janedoe",
               "https://en.wikipedia.org/wiki/Jane_Doe",
               ~s(A quote with "quotes", commas, and\na newline),
               "against",
               "2023-05-10",
               "day",
               "https://example.com/article",
               "verified",
               "source checked",
               today,
               "ai_verified",
               "on topic",
               today,
               "disputed",
               "answer looks wrong",
               today
             ]

      refute body =~ "old quote comment"
    end

    test "excludes user opinions without a source", %{conn: conn} do
      statement = statement_fixture()
      author = author_fixture()

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          content: "an unsourced user opinion",
          source_url: nil
        })

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      {:ok, _} =
        Votes.create_vote(%{
          author_id: author.id,
          statement_id: statement.id,
          opinion_id: opinion.id,
          answer: :for
        })

      conn = get(conn, ~p"/p/#{statement.slug}/quotes.csv")

      body = response(conn, 200)
      assert CSV.parse_string(body) == []
      refute body =~ "an unsourced user opinion"
    end

    test "returns 404 for an unknown slug", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, ~p"/p/unknown-statement/quotes.csv")
      end
    end
  end
end
