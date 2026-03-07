defmodule YouCongressWeb.MCPServer.OpinionsShow do
  @moduledoc """
  Show a single opinion by identifier.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions

  @not_found_message "Opinion not found."

  schema do
    field :opinion_id, :integer, required: true
  end

  def execute(%{opinion_id: opinion_id}, frame) do
    case Opinions.get_opinion(opinion_id) do
      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      opinion ->
        data = %{opinion: take_fields(opinion)}
        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp take_fields(opinion) do
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
      user_id: opinion.user_id
    }
  end
end
