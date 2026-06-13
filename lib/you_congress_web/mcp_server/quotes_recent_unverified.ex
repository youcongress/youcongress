defmodule YouCongressWeb.MCPServer.QuotesRecentUnverified do
  @moduledoc """
  Return the most recent unverified quote plus the statements and votes that already use it.
  We skip quotes with source_url starting with twitter, x, youtube as AI is not able to access them.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.MCP.ToolUsageTracker
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes

  @no_quote_message "No unverified quotes available."
  @unsupported_source_prefixes [
    "https://twitter.com",
    "https://x.com",
    "https://www.youtube.com"
  ]

  schema do
  end

  @impl true
  def execute(_params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    case recent_unverified_quote() do
      nil ->
        {:reply, Response.error(Response.tool(), @no_quote_message), frame}

      opinion ->
        votes = votes_by_statement(opinion)
        relevance = relevance_by_statement(opinion)

        data = %{
          quote: serialize_quote(opinion),
          statements: serialize_statements(opinion, votes, relevance)
        }

        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp recent_unverified_quote do
    opts = [
      has_statements: true,
      only_quotes: true,
      needs_verification: true,
      order_by: [desc: :id],
      preload: [:author, :statements, :opinion_statements],
      exclude_source_prefixes: @unsupported_source_prefixes
    ]

    Opinions.get_opinion(opts)
  end

  defp votes_by_statement(%{id: opinion_id}) do
    Votes.list_votes(opinion_ids: [opinion_id], preload: [:author])
    |> Enum.reduce(%{}, fn vote, acc ->
      Map.put(acc, vote.statement_id, vote)
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
