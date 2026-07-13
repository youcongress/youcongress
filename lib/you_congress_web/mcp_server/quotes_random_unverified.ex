defmodule YouCongressWeb.MCPServer.QuotesRandomUnverified do
  @moduledoc """
  Return random quotes with pending reviewable verification work plus the statements and votes that already use them.
  Returns 10 quotes by default; pass `count` to change it (max 100).
  We skip quotes with source_url starting with twitter, x, youtube as AI is not able to access them.
  """

  use Anubis.Server.Component, type: :tool

  import Ecto.Query, warn: false
  require Ecto.Query

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker

  @no_quote_message "No quotes needing verification review available."
  @default_count 10
  @max_count 100
  @unsupported_source_prefixes [
    "https://twitter.com",
    "https://x.com",
    "https://www.youtube.com"
  ]

  schema do
    field :count, :integer, default: @default_count
  end

  @impl true
  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    case random_unverified_quotes(count(params)) do
      [] ->
        {:reply, Response.error(Response.tool(), @no_quote_message), frame}

      opinions ->
        data = %{quotes: Enum.map(opinions, &serialize/1)}

        {:reply, Response.json(Response.tool(), data), frame}
    end
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

  defp random_unverified_quotes(count) do
    random_order = dynamic([q], fragment("RANDOM()"))

    opts = [
      has_statements: true,
      only_quotes: true,
      needs_quote_review: true,
      limit: count,
      order_by: random_order,
      preload: [:author, :statements, :opinion_statements],
      exclude_source_prefixes: @unsupported_source_prefixes
    ]

    Opinions.list_opinions(opts)
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
