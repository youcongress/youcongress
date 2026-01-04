defmodule YouCongressWeb.MCPServer.OpinionsSearch do
  @moduledoc "Search quotes and authors on YouCongress."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions

  schema do
    field :query, :string, required: false
    field :statement_ids, :array, required: false
  end

  def execute(params, frame) do
    query = Map.get(params, :query)
    statement_id = Map.get(params, :statement_id)

    opinions_args = [preload: [:author], limit: 100]

    opinions_args =
      if query do
        [{:search, query} | opinions_args]
      else
        opinions_args
      end

    opinions_args =
      if statement_id do
        [{:statement_ids, [statement_id]} | opinions_args]
      else
        opinions_args
      end

    opinions =
      opinions_args
      |> Opinions.list_opinions()
      |> Enum.map(fn opinion ->
        %{
          quote: opinion.content,
          author: opinion.author.name,
          source_url: opinion.source_url
        }
      end)

    data = %{
      quotes: opinions
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end
end
