defmodule YouCongressWeb.MCPServer.QuotesSearch do
  @moduledoc "Search quotes on YouCongress for a given statement (policy proposal or claim)."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions

  @limit 250

  schema do
    # We force LLMs to provide statement_id because:
    # - Listing statements first and then getting many quotes within a statement works best for now
    # - If we make it optional, LLMs rarely use it
    # - We don't have tons of quotes yet
    field :statement_id, :integer, required: true
    field :query, :string, required: true
  end

  def execute(params, frame) do
    statement_id = Map.get(params, :statement_id)
    query = Map.get(params, :query)

    opinions = find_opinions(query, statement_id)
    more_opinions = more_opinions(statement_id, opinions)

    data = %{
      matches: take_fields(opinions),
      more_quotes: take_fields(more_opinions)
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp find_opinions(query, statement_id) do
    [statement_ids: [statement_id], search: query, limit: @limit, preload: :author]
    |> Opinions.list_opinions()
  end

  defp more_opinions(statement_id, opinions) do
    opinions_ids = Enum.map(opinions, & &1.id)
    opinions_count = length(opinions_ids)

    Opinions.list_opinions(
      statement_ids: [statement_id],
      limit: @limit - opinions_count,
      exclude_ids: opinions_ids,
      preload: :author
    )
  end

  defp take_fields(opinions) do
    Enum.map(opinions, fn opinion ->
      %{
        quote: opinion.content,
        author: opinion.author.name,
        author_biography: opinion.author.bio,
        source_url: opinion.source_url,
        year: opinion.year,
        verified_by_humans: !!opinion.verified_at
      }
    end)
  end
end
