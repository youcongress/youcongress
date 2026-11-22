defmodule YouCongressWeb.MCPServer.QuotesRecentUnverified do
  @moduledoc """
  Return the most recent quotes with pending reviewable verification work plus the statements and votes that already use them.
  Returns 25 quotes by default; pass `count` to change it (max 100). Pass the
  `last_id` from a response with `has_more: true` to get the next page.
  We skip quotes with source_url starting with youtube as AI is not able to access them.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.MCP.ToolUsageTracker
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongressWeb.MCPServer.ListPagination

  @default_count 25
  @max_count 100
  @unsupported_source_prefixes [
    "https://www.youtube.com"
  ]

  schema do
    field :count, :integer,
      default: @default_count,
      description: "Quotes per page. Defaults to 25 and is capped at 100."

    field :last_id, :integer,
      description:
        "Cursor for the next page. When has_more is true, pass the previous response's last_id."
  end

  @impl true
  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    count = count(params)
    results = recent_unverified_quotes(params, count + 1)
    has_more = length(results) > count
    opinions = Enum.take(results, count)

    data = %{
      quotes: Enum.map(opinions, &serialize/1),
      last_id: ListPagination.last_id(opinions),
      has_more: has_more
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp count(params) do
    params
    |> Map.get(:count, @default_count)
    |> Kernel.||(@default_count)
    |> max(1)
    |> min(@max_count)
  end

  defp serialize(opinion) do
    votes = votes_by_statement(opinion)
    relevance = relevance_by_statement(opinion)

    %{
      quote: serialize_quote(opinion),
      statements: serialize_statements(opinion, votes, relevance)
    }
  end

  defp recent_unverified_quotes(params, count) do
    [
      has_statements: true,
      only_quotes: true,
      needs_quote_review: true,
      limit: count,
      order_by: [desc: :id],
      preload: [:author, :statements, :opinion_statements],
      exclude_source_prefixes: @unsupported_source_prefixes
    ]
    |> ListPagination.maybe_paginate(params)
    |> Opinions.list_opinions()
  end

  defp votes_by_statement(%{id: opinion_id, author_id: author_id}) do
    Votes.list_votes(opinion_ids: [opinion_id], preload: [:author])
    |> Enum.group_by(& &1.statement_id)
    |> Map.new(fn {statement_id, votes} ->
      vote =
        Enum.find(votes, &(&1.author_id == author_id)) ||
          List.first(votes)

      {statement_id, vote}
    end)
  end

  defp relevance_by_statement(%{opinion_statements: opinion_statements})
       when is_list(opinion_statements) do
    Enum.reduce(opinion_statements, %{}, fn os, acc ->
      Map.put(acc, os.statement_id, os.verification_status || :unverified)
    end)
  end

  defp relevance_by_statement(_), do: %{}

  defp serialize_quote(opinion) do
    opinion
    |> Opinion.serialized_date_fields()
    |> Map.merge(%{
      opinion_id: opinion.id,
      quote: opinion.content,
      author_id: opinion.author_id,
      author_name: opinion.author && opinion.author.name,
      author_biography: opinion.author && opinion.author.bio,
      source_url: opinion.source_url,
      source_text: opinion.source_text,
      verification_status: verification_status(opinion)
    })
  end

  defp verification_status(%{verification_status: nil}), do: :unverified
  defp verification_status(%{verification_status: status}), do: status

  defp serialize_statements(opinion, vote_map, relevance_map) do
    opinion.statements
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn statement ->
      vote = Map.get(vote_map, statement.id)

      %{
        statement_id: statement.id,
        statement_title: statement.title,
        relevance_status: Map.get(relevance_map, statement.id, :unverified),
        vote: serialize_vote(vote)
      }
    end)
  end

  defp serialize_vote(nil), do: nil

  defp serialize_vote(vote) do
    %{
      vote_id: vote.id,
      answer: vote.answer,
      author_id: vote.author_id,
      author_name: vote.author && vote.author.name,
      direct: vote.direct,
      verification_status: vote.verification_status || :unverified
    }
  end
end
