defmodule YouCongressWeb.MCPServer.QuotesRecentUnverifiedTest do
  use ExUnit.Case, async: false

  import Mock

  alias YouCongressWeb.MCPServer.QuotesRecentUnverified

  describe "execute/2" do
    test "returns the most recent unverified quote with statements and votes" do
      opinion = %{
        id: 31,
        content: "We need to tax carbon to save the planet.",
        author_id: 12,
        author: %{name: "Ada", bio: "Climate advocate"},
        source_url: "https://example.com/carbon-tax",
        year: 2024,
        verification_status: nil,
        statements: [%{id: 8, title: "Tax carbon emissions"}]
      }

      vote = %{
        id: 18,
        statement_id: 8,
        answer: :for,
        author_id: 12,
        author: %{name: "Ada"},
        direct: true
      }

      with_mocks([
        {Anubis.Server.Response, [],
         [
           tool: fn -> :tool end,
           json: fn :tool, data -> {:json, data} end,
           error: fn :tool, message -> {:error, message} end
         ]},
        {YouCongress.Opinions, [],
         [
           get_opinion: fn opts ->
             assert opts[:has_statements] == true
             assert opts[:only_quotes] == true
             assert opts[:is_verified] == false
             assert opts[:order_by] == [desc: :id]
             assert opts[:preload] == [:author, :statements]
             assert opts[:exclude_source_prefixes] == unsupported_source_prefixes()
             opinion
           end
         ]},
        {YouCongress.Votes, [],
         [
           list_votes: fn opts ->
             assert opts == [opinion_ids: [31], preload: [:author]]
             [vote]
           end
         ]}
      ]) do
        assert {:reply, {:json, %{quote: quote_payload, statements: [statement_payload]}}, :frame} =
                 QuotesRecentUnverified.execute(%{}, :frame)

        assert quote_payload.opinion_id == opinion.id
        assert quote_payload.quote == opinion.content
        assert statement_payload.statement_id == 8
        assert statement_payload.statement_title == "Tax carbon emissions"
        assert statement_payload.vote.vote_id == vote.id
        assert statement_payload.vote.answer == :for
      end
    end

    test "passes unsupported source prefixes to the query" do
      allowed_article = %{
        id: 41,
        content: "We must end partisan gerrymandering immediately.",
        author_id: 4,
        author: %{name: "Lin", bio: "Election reform advocate"},
        source_url: "https://example.com/opinion",
        year: 2024,
        verification_status: nil,
        statements: [%{id: 10, title: "End partisan gerrymandering"}]
      }

      with_mocks([
        {Anubis.Server.Response, [],
         [
           tool: fn -> :tool end,
           json: fn :tool, data -> {:json, data} end,
           error: fn :tool, message -> {:error, message} end
         ]},
        {YouCongress.Opinions, [],
         [
           get_opinion: fn opts ->
             assert opts[:order_by] == [desc: :id]
             assert opts[:exclude_source_prefixes] == unsupported_source_prefixes()
             allowed_article
           end
         ]},
        {YouCongress.Votes, [], [list_votes: fn _opts -> [] end]}
      ]) do
        assert {:reply, {:json, %{quote: quote_payload}}, :frame} =
                 QuotesRecentUnverified.execute(%{}, :frame)

        assert quote_payload.opinion_id == allowed_article.id
        assert quote_payload.source_url == "https://example.com/opinion"
      end
    end

    test "returns deterministic error when no unverified quotes exist" do
      with_mocks([
        {Anubis.Server.Response, [],
         [
           tool: fn -> :tool end,
           json: fn :tool, data -> {:json, data} end,
           error: fn :tool, message -> {:error, message} end
         ]},
        {YouCongress.Opinions, [], [get_opinion: fn _opts -> nil end]}
      ]) do
        assert {:reply, {:error, "No unverified quotes available."}, :frame} =
                 QuotesRecentUnverified.execute(%{}, :frame)
      end
    end
  end

  defp unsupported_source_prefixes do
    [
      "https://twitter.com",
      "https://x.com",
      "https://www.youtube.com"
    ]
  end
end
