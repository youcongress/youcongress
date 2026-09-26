defmodule YouCongressWeb.MCPServer.QuotesSearch do
  @moduledoc """
  Search quotes on YouCongress.

  With a statement_id, performs a keyword search for quotes within that statement
  (policy proposal or claim); this is public. Without a statement_id, performs a
  general semantic similarity search across all statements, returning quotes
  ranked by how closely their meaning matches the query (each with a similarity
  score, 0.0 to 1.0). Cross-statement semantic search requires a valid API key
  (pass `?key=YOUR_KEY` in the MCP request URL).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker

  @limit 250

  # Accepted values for the `statuses` filter. "unverified" maps to a nil
  # verification_status; the rest mirror the Opinion verification_status enum.
  @statuses ~w(unverified verified ai_verified ai_unverifiable endorsed disputed unverifiable)

  @missing_key_message "Cross-statement semantic search requires an API key. Pass ?key=YOUR_KEY in the MCP request URL, or provide a statement_id to keyword-search within a single statement."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API, or provide a statement_id to keyword-search within a single statement."

  schema do
    # statement_id is optional:
    # - With it: keyword search within that statement (works best when you already
    #   know the statement; list statements first, then drill into one). Public.
    # - Without it: semantic similarity search across all statements. Requires a
    #   valid API key because it generates an embedding.
    field :statement_id, :integer
    field :query, :string, required: true

    # Optional filter: only return quotes whose verification_status is one of
    # these. Use "unverified" for quotes that have not been verified yet.
    field :statuses, {:list, {:enum, @statuses}},
      description:
        "Only return quotes with one of these verification statuses. Options: #{Enum.join(@statuses, ", ")}."
  end

  def execute(params, frame) do
    user_result = ToolUsageTracker.track(__MODULE__, frame, required_scope: :read)

    query = Map.get(params, :query)
    statuses = parse_statuses(Map.get(params, :statuses))

    case Map.get(params, :statement_id) do
      nil -> semantic_search(query, statuses, frame, user_result)
      statement_id -> statement_search(query, statement_id, statuses, frame)
    end
  end

  defp statement_search(query, statement_id, statuses, frame) do
    opinions = find_opinions(query, statement_id, statuses)
    more_opinions = more_opinions(statement_id, opinions, statuses)
    all_opinions = opinions ++ more_opinions
    vote_map = votes_by_opinion(all_opinions)

    data = %{
      matches: take_fields(opinions, vote_map),
      more_quotes: take_fields(more_opinions, vote_map)
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp semantic_search(query, statuses, frame, user_result) do
    case user_result do
      {:ok, _user} ->
        opinions =
          query
          |> Opinions.get_by_content_similarity(statuses: statuses)
          |> Repo.preload(:author)

        vote_map = votes_by_opinion(opinions)

        data = %{
          matches: take_fields(opinions, vote_map),
          more_quotes: []
        }

        {:reply, Response.json(Response.tool(), data), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, _} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}
    end
  end

  defp find_opinions(query, statement_id, statuses) do
    [
      statement_ids: [statement_id],
      search: query,
      statuses: statuses,
      limit: @limit,
      preload: :author
    ]
    |> Opinions.list_opinions()
  end

  defp more_opinions(statement_id, opinions, statuses) do
    opinions_ids = Enum.map(opinions, & &1.id)
    opinions_count = length(opinions_ids)

    Opinions.list_opinions(
      statement_ids: [statement_id],
      statuses: statuses,
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

  # Turns the incoming string statuses into the values the query expects:
  # "unverified" becomes nil (no verification_status), the rest become atoms.
  defp parse_statuses(statuses) when is_list(statuses) and statuses != [] do
    Enum.map(statuses, fn
      "unverified" -> nil
      status -> String.to_existing_atom(status)
    end)
  end

  defp parse_statuses(_statuses), do: nil
end
