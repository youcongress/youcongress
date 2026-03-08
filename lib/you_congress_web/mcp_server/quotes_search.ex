defmodule YouCongressWeb.MCPServer.QuotesSearch do
  @moduledoc "Search quotes on YouCongress for a given statement (policy proposal or claim)."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Votes

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
    vote_map = votes_by_opinion(opinions ++ more_opinions)

    data = %{
      matches: take_fields(opinions, vote_map),
      more_quotes: take_fields(more_opinions, vote_map)
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

  defp votes_by_opinion([]), do: %{}

  defp votes_by_opinion(opinions) do
    opinion_ids =
      opinions
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case opinion_ids do
      [] ->
        %{}

      ids ->
        Votes.list_votes(opinion_ids: ids)
        |> Enum.reduce(%{}, fn vote, acc ->
          Map.put(acc, vote.opinion_id, vote)
        end)
    end
  end

  defp take_fields(opinions, vote_map) do
    Enum.map(opinions, fn opinion ->
      vote = Map.get(vote_map, opinion.id)

      %{
        opinion_id: opinion.id,
        quote: opinion.content,
        author: opinion.author.name,
        author_biography: opinion.author.bio,
        source_url: opinion.source_url,
        year: opinion.year,
        verified_by_humans: opinion.verification_status != nil,
        vote_id: vote && vote.id,
        vote_answer: vote && vote.answer
      }
    end)
  end
end
