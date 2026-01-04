defmodule YouCongressWeb.MCPServer.OpinionsSearch do
  @moduledoc "Search quotes and authors on YouCongress."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions

  schema do
    field :query, :string, required: false
    field :statement_id, :string, required: false
  end

  def execute(params, frame) do
    statement_id = Map.get(params, :statement_id)
    statement_id = if statement_id, do: String.to_integer(statement_id), else: nil
    query = if statement_id, do: nil, else: Map.get(params, :query)

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
          source_url: opinion.source_url,
          year: opinion.year
        }
      end)

    data = %{
      quotes: opinions
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end
end
