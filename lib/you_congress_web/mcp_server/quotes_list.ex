defmodule YouCongressWeb.MCPServer.QuotesList do
  @moduledoc """
  List quotes on YouCongress.
  Returns 250 quotes per page by default (maximum 500), ordered by id or by the
  date of the quote when `order_by` is "date". `order` controls the direction
  ("desc" by default, or "asc"). Quotes without a date are returned last when
  ordering by date. Pass the `last_id` from a response with `has_more: true` to
  get the next page.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker
  alias YouCongressWeb.MCPServer.ListPagination

  schema do
    field :last_id, :integer,
      description:
        "Cursor for the next page. When has_more is true, pass the previous response's last_id."

    field :count, :integer,
      default: 250,
      description: "Quotes per page. Defaults to 250 and is capped at 500."

    field :order_by, :string, default: "id"
    field :order, :string, default: "desc"
  end

  @default_count 250
  @max_count 500

  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    count = count(params)

    results =
      [only_quotes: true, limit: count + 1, order_by: order_by(params), preload: :author]
      |> maybe_paginate(params)
      |> Opinions.list_opinions()

    has_more = length(results) > count
    opinions = Enum.take(results, count)
    vote_map = votes_by_opinion(opinions)

    data = %{
      quotes: take_fields(opinions, vote_map),
      last_id: ListPagination.last_id(opinions),
      has_more: has_more
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp order_by(params) do
    case {Map.get(params, :order_by, "id"), ListPagination.order(params)} do
      {"date", :asc} -> [asc_nulls_last: :date, asc: :id]
      {"date", :desc} -> [desc_nulls_last: :date, desc: :id]
      {_, :asc} -> [asc: :id]
      {_, :desc} -> [desc: :id]
    end
  end

  defp maybe_paginate(opts, %{order_by: "date", last_id: last_id} = params) do
    case Opinions.get_opinion(last_id) do
      nil ->
        ListPagination.maybe_paginate(opts, params)

      opinion ->
        Keyword.put(
          opts,
          :quote_date_cursor,
          {ListPagination.order(params), opinion.date, last_id}
        )
    end
  end

  defp maybe_paginate(opts, params), do: ListPagination.maybe_paginate(opts, params)

  defp count(params) do
    params
    |> Map.get(:count, @default_count)
    |> Kernel.||(@default_count)
    |> max(1)
    |> min(@max_count)
  end

  defp votes_by_opinion([]), do: %{}

  defp votes_by_opinion(opinions) do
    opinion_ids = Enum.map(opinions, & &1.id)

    Votes.list_votes(opinion_ids: opinion_ids)
    |> Enum.reduce(%{}, fn vote, acc ->
      Map.put(acc, vote.opinion_id, vote)
    end)
  end

  defp take_fields(opinions, vote_map) do
    Enum.map(opinions, fn opinion ->
      vote = Map.get(vote_map, opinion.id)

      opinion
      |> Opinion.serialized_date_fields()
      |> Map.merge(%{
        opinion_id: opinion.id,
        quote: opinion.content,
        author: opinion.author && opinion.author.name,
        author_biography: opinion.author && opinion.author.bio,
        source_url: opinion.source_url,
        source_text: opinion.source_text,
        verification_status: verification_status(opinion),
        vote_id: vote && vote.id,
        vote_answer: vote && vote.answer
      })
    end)
  end

  defp verification_status(%{verification_status: nil}), do: :unverified
  defp verification_status(%{verification_status: status}), do: status
end
