defmodule YouCongressWeb.MCPServer.OpinionsShow do
  @moduledoc """
  Show a single opinion by identifier.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions
  alias YouCongress.Votes

  @not_found_message "Opinion not found."

  schema do
    field :opinion_id, :integer, required: true
  end

  def execute(%{opinion_id: opinion_id}, frame) do
    case Opinions.get_opinion(opinion_id, preload: [:statements]) do
      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      opinion ->
        data = %{opinion: take_fields(opinion)}
        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp take_fields(opinion) do
    votes_by_statement_id = votes_by_statement_id(opinion)

    %{
      opinion_id: opinion.id,
      content: opinion.content,
      source_url: opinion.source_url,
      year: opinion.year,
      twin: opinion.twin,
      verification_status: opinion.verification_status,
      ancestry: opinion.ancestry,
      descendants_count: opinion.descendants_count,
      likes_count: opinion.likes_count,
      author_id: opinion.author_id,
      user_id: opinion.user_id,
      statements: take_statement_fields(opinion.statements, votes_by_statement_id)
    }
  end

  defp votes_by_statement_id(%{author_id: nil}), do: %{}
  defp votes_by_statement_id(%{statements: []}), do: %{}

  defp votes_by_statement_id(%{author_id: author_id, statements: statements}) do
    statement_ids = Enum.map(statements, & &1.id)

    Votes.list_votes(author_ids: [author_id], statement_ids: statement_ids)
    |> Map.new(fn vote -> {vote.statement_id, vote} end)
  end

  defp take_statement_fields(statements, votes_by_statement_id) do
    statements
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn statement ->
      vote = Map.get(votes_by_statement_id, statement.id)

      %{
        statement_id: statement.id,
        statement_title: statement.title,
        vote_id: vote && vote.id,
        vote_answer: vote && to_string(vote.answer)
      }
    end)
  end
end
