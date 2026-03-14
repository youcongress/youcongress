defmodule YouCongressWeb.MCPServer.QuotesRandomUnverified do
  @moduledoc """
  Return a random unverified quote plus the statements and votes that already use it.
  """

  use Anubis.Server.Component, type: :tool

  import Ecto.Query, warn: false
  require Ecto.Query

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Votes

  @no_quote_message "No unverified quotes available."

  schema do
  end

  @impl true
  def execute(_params, frame) do
    case random_unverified_quote() do
      nil ->
        {:reply, Response.error(Response.tool(), @no_quote_message), frame}

      opinion ->
        votes = votes_by_statement(opinion)

        data = %{
          quote: serialize_quote(opinion),
          statements: serialize_statements(opinion, votes)
        }

        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp random_unverified_quote do
    random_order = dynamic([q], fragment("RANDOM()"))

    opts = [
      has_statements: true,
      only_quotes: true,
      verification_status: "unverified",
      limit: 1,
      order_by: random_order,
      preload: [:author, :statements]
    ]

    case Opinions.list_opinions(opts) do
      [opinion | _] -> opinion
      _ -> nil
    end
  end

  defp votes_by_statement(%{id: opinion_id}) do
    Votes.list_votes(opinion_ids: [opinion_id], preload: [:author])
    |> Enum.reduce(%{}, fn vote, acc ->
      Map.put(acc, vote.statement_id, vote)
    end)
  end

  defp serialize_quote(opinion) do
    %{
      opinion_id: opinion.id,
      quote: opinion.content,
      author_id: opinion.author_id,
      author_name: opinion.author && opinion.author.name,
      author_biography: opinion.author && opinion.author.bio,
      source_url: opinion.source_url,
      year: opinion.year,
      verified_by_humans: opinion.verification_status != nil
    }
  end

  defp serialize_statements(opinion, vote_map) do
    opinion.statements
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn statement ->
      vote = Map.get(vote_map, statement.id)

      %{
        statement_id: statement.id,
        statement_title: statement.title,
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
      direct: vote.direct
    }
  end
end
