defmodule YouCongressWeb.MCPServer.QuotesList do
  @moduledoc """
  List quotes on YouCongress.
  Returns up to 100 quotes ordered by id ("desc" by default, newest first, or "asc").
  Pass the last_id from a previous response to get the next page.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker
  alias YouCongressWeb.MCPServer.ListPagination

  schema do
    field :last_id, :integer
    field :order, :string, default: "desc"
  end

  @limit 100

  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    opinions =
      [only_quotes: true, limit: @limit, order_by: order_by(params), preload: :author]
      |> ListPagination.maybe_paginate(params)
      |> Opinions.list_opinions()

    vote_map = votes_by_opinion(opinions)

    data = %{
      quotes: take_fields(opinions, vote_map),
      last_id: ListPagination.last_id(opinions)
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp order_by(params) do
    case ListPagination.order(params) do
      :asc -> [asc: :id]
      :desc -> [desc: :id]
    end
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
