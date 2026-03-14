defmodule YouCongressWeb.MCPServer.OpinionsShow do
  @moduledoc """
  Show a single opinion by identifier.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ecto.Association.NotLoaded
  alias YouCongress.Opinions
  alias YouCongress.Votes
  alias YouCongress.Votes

  @not_found_message "Opinion not found."

  schema do
    field :opinion_id, :integer, required: true
  end

  @impl true
  def execute(%{opinion_id: opinion_id}, frame) do
    case fetch_opinion(opinion_id) do
      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      opinion ->
        {:reply, Response.json(Response.tool(), %{opinion: serialize_opinion(opinion)}), frame}
    end
  end

  defp fetch_opinion(opinion_id) do
    Opinions.get_opinion(opinion_id, preload: [:statements])
  end

  defp serialize_opinion(opinion) do
    %{
      opinion_id: opinion.id,
      content: opinion.content,
      source_url: opinion.source_url,
      year: opinion.year,
      author_id: opinion.author_id,
      user_id: opinion.user_id,
      verification_status: opinion.verification_status,
      statements: serialize_statements(opinion)
    }
  end

  defp serialize_statements(%{statements: %NotLoaded{}}), do: []

  defp serialize_statements(%{statements: statements, author_id: author_id}) do
    statements = statements || []
    votes_map = votes_by_statement(statements, author_id)

    statements
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn statement ->
      vote = Map.get(votes_map, statement.id)

      %{
        statement_id: statement.id,
        statement_title: statement.title,
        vote_id: vote && vote.id,
        vote_answer: vote && vote.answer
      }
    end)
  end

  defp votes_by_statement(_statements, nil), do: %{}
  defp votes_by_statement([], _author_id), do: %{}

  defp votes_by_statement(statements, author_id) do
    statement_ids =
      statements
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    case statement_ids do
      [] ->
        %{}

      ids ->
        Votes.list_votes(author_ids: [author_id], statement_ids: ids)
        |> Enum.reduce(%{}, fn vote, acc ->
          Map.put(acc, vote.statement_id, vote)
        end)
    end
  end
end
