defmodule YouCongressWeb.MCPServer.QuotesSearch do
  @moduledoc """
  Search quotes on YouCongress.

  With a statement_id, performs a keyword search for quotes within that statement
  (policy proposal or claim). Without a statement_id, performs a general semantic
  similarity search across all statements, returning quotes ranked by how closely
  their meaning matches the query (each with a similarity score, 0.0–1.0).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker

  @limit 250

  schema do
    # statement_id is optional:
    # - With it: keyword search within that statement (works best when you already
    #   know the statement — list statements first, then drill into one).
    # - Without it: semantic similarity search across all statements.
    field :statement_id, :integer
    field :query, :string, required: true
  end

  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    query = Map.get(params, :query)

    case Map.get(params, :statement_id) do
      nil -> semantic_search(query, frame)
      statement_id -> statement_search(query, statement_id, frame)
    end
  end

  defp statement_search(query, statement_id, frame) do
    opinions = find_opinions(query, statement_id)
    more_opinions = more_opinions(statement_id, opinions)
    all_opinions = opinions ++ more_opinions
    vote_map = votes_by_opinion(all_opinions)

    data = %{
      matches: take_fields(opinions, vote_map),
      more_quotes: take_fields(more_opinions, vote_map)
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp semantic_search(query, frame) do
    opinions =
      query
      |> Opinions.get_by_content_similarity()
      |> Repo.preload(:author)

    vote_map = votes_by_opinion(opinions)

    data = %{
      matches: take_fields(opinions, vote_map),
      more_quotes: []
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

      base =
        opinion
        |> Opinion.serialized_date_fields()
        |> Map.merge(%{
          opinion_id: opinion.id,
          quote: opinion.content,
          author: opinion.author.name,
          author_biography: opinion.author.bio,
          source_url: opinion.source_url,
          source_text: opinion.source_text,
          verification_status: verification_status(opinion),
          vote_id: vote && vote.id,
          vote_answer: vote && vote.answer
        })

      case opinion.similarity do
        nil -> base
        similarity -> Map.put(base, :similarity, similarity)
      end
    end)
  end

  defp verification_status(%{verification_status: nil}), do: :unverified
  defp verification_status(%{verification_status: status}), do: status
end
