defmodule YouCongressWeb.MCPServer.QuotesSearch do
  @moduledoc """
  Search quotes on YouCongress.

  With a statement_id, performs a keyword search for quotes within that statement
  (policy proposal or claim); this is public. Without a statement_id, performs a
  general semantic similarity search across all statements, returning quotes
  ranked by how closely their meaning matches the query (each with a similarity
  score, 0.0 to 1.0). Cross-statement semantic search requires a valid API key
  (pass `?key=YOUR_KEY` in the MCP request URL).

  Results are paginated with `offset` and `count` (250 by default, maximum 500).
  Pass `next_offset` from one response as `offset` in the next request until it
  is null.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker

  @default_count 250
  @max_count 500

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

    field :offset, :integer,
      default: 0,
      description:
        "Pagination offset. Pass the previous response's next_offset to fetch the next page."

    field :count, :integer,
      default: @default_count,
      description: "Results per page. Defaults to 250 and is capped at 500."

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
    offset = offset(params)
    count = count(params)

    case Map.get(params, :statement_id) do
      nil -> semantic_search(query, statuses, offset, count, frame, user_result)
      statement_id -> statement_search(query, statement_id, statuses, offset, count, frame)
    end
  end

  defp statement_search(query, statement_id, statuses, offset, count, frame) do
    matching_count = matching_count(query, statement_id, statuses)
    total_count = total_count(statement_id, statuses)

    {opinions, more_opinions} =
      statement_page(query, statement_id, statuses, matching_count, offset, count)

    all_opinions = opinions ++ more_opinions
    vote_map = votes_by_opinion(all_opinions)
    returned_count = length(all_opinions)

    data = %{
      matches: take_fields(opinions, vote_map),
      more_quotes: take_fields(more_opinions, vote_map),
      total_count: total_count,
      next_offset: next_offset(offset, returned_count, total_count)
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp semantic_search(query, statuses, offset, count, frame, user_result) do
    case user_result do
      {:ok, _user} ->
        results =
          query
          |> Opinions.get_by_content_similarity(
            statuses: statuses,
            offset: offset,
            limit: count + 1
          )
          |> Repo.preload(:author)

        has_more = length(results) > count
        opinions = Enum.take(results, count)
        vote_map = votes_by_opinion(opinions)

        data = %{
          matches: take_fields(opinions, vote_map),
          more_quotes: [],
          next_offset: if(has_more, do: offset + length(opinions), else: nil)
        }

        {:reply, Response.json(Response.tool(), data), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, _} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}
    end
  end

  defp statement_page(query, statement_id, statuses, matching_count, offset, count)
       when offset < matching_count do
    opinions =
      Opinions.list_opinions(
        statement_opts(statement_id, statuses) ++
          [search: query, order_by: [desc: :id], offset: offset, limit: count, preload: :author]
      )

    remaining = count - length(opinions)

    more_opinions =
      if remaining > 0 do
        find_nonmatching_opinions(query, statement_id, statuses, 0, remaining)
      else
        []
      end

    {opinions, more_opinions}
  end

  defp statement_page(query, statement_id, statuses, matching_count, offset, count) do
    more_offset = offset - matching_count
    {[], find_nonmatching_opinions(query, statement_id, statuses, more_offset, count)}
  end

  defp find_nonmatching_opinions(query, statement_id, statuses, offset, count) do
    Opinions.list_opinions(
      statement_opts(statement_id, statuses) ++
        [
          exclude_search: query,
          order_by: [desc: :id],
          offset: offset,
          limit: count,
          preload: :author
        ]
    )
  end

  defp matching_count(query, statement_id, statuses) do
    Opinions.count(statement_opts(statement_id, statuses) ++ [search: query])
  end

  defp total_count(statement_id, statuses) do
    Opinions.count(statement_opts(statement_id, statuses))
  end

  defp statement_opts(statement_id, statuses) do
    [statement_ids: [statement_id], only_quotes: true, statuses: statuses]
  end

  defp next_offset(offset, returned_count, total_count)
       when offset + returned_count < total_count,
       do: offset + returned_count

  defp next_offset(_offset, _returned_count, _total_count), do: nil

  defp offset(params) do
    params
    |> Map.get(:offset, 0)
    |> Kernel.||(0)
    |> max(0)
  end

  defp count(params) do
    params
    |> Map.get(:count, @default_count)
    |> Kernel.||(@default_count)
    |> max(1)
    |> min(@max_count)
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
