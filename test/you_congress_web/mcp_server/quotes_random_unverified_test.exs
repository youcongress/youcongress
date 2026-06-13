defmodule YouCongressWeb.MCPServer.QuotesRandomUnverifiedTest do
  use ExUnit.Case, async: false

  import Mock

  alias YouCongressWeb.MCPServer.QuotesRandomUnverified

  describe "execute/2" do
    test "returns a random unverified quote with statements and votes" do
      opinion = %{
        id: 11,
        content: "We need to tax carbon to save the planet.",
        author_id: 7,
        author: %{name: "Ada", bio: "Climate advocate"},
        source_url: "https://example.com/carbon-tax",
        year: 2024,
        verification_status: nil,
        statements: [%{id: 3, title: "Tax carbon emissions"}]
      }

      vote = %{
        id: 13,
        statement_id: 3,
        answer: :for,
        author_id: 7,
        author: %{name: "Ada"},
        direct: true,
        verification_status: nil
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
             assert opts[:needs_verification] == true
             assert opts[:preload] == [:author, :statements, :opinion_statements]
             assert opts[:exclude_source_prefixes] == unsupported_source_prefixes()
             assert opts[:order_by] != nil
             opinion
           end
         ]},
        {YouCongress.Votes, [],
         [
           list_votes: fn opts ->
             assert opts == [opinion_ids: [11], preload: [:author]]
             [vote]
           end
         ]}
      ]) do
        assert {:reply, {:json, %{quote: quote_payload, statements: [statement_payload]}}, :frame} =
                 QuotesRandomUnverified.execute(%{}, :frame)

        assert quote_payload.opinion_id == opinion.id
        assert quote_payload.quote == opinion.content
        assert statement_payload.statement_id == 3
        assert statement_payload.statement_title == "Tax carbon emissions"
        assert statement_payload.vote.vote_id == vote.id
        assert statement_payload.vote.answer == :for
      end
    end

    test "passes unsupported source prefixes to the query" do
      allowed_article = %{
        id: 22,
        content: "We must end partisan gerrymandering immediately.",
        author_id: 9,
        author: %{name: "Lin", bio: "Election reform advocate"},
        source_url: "https://example.com/opinion",
        year: 2024,
        verification_status: nil,
        statements: [%{id: 5, title: "End partisan gerrymandering"}]
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
             assert opts[:exclude_source_prefixes] == unsupported_source_prefixes()
             assert opts[:order_by] != nil
             allowed_article
           end
         ]},
        {YouCongress.Votes, [], [list_votes: fn _opts -> [] end]}
      ]) do
        assert {:reply, {:json, %{quote: quote_payload}}, :frame} =
                 QuotesRandomUnverified.execute(%{}, :frame)

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
                 QuotesRandomUnverified.execute(%{}, :frame)
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
