defmodule YouCongressWeb.MCPServer.Search do
  @moduledoc "Search quotes and authors on YouCongress."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Opinions

  schema do
    field :query, :string, required: true
  end

  def execute(%{query: query}, frame) do
    opinions =
      [search: query, preload: [:author]]
      |> Opinions.list_opinions()
      |> Enum.map(fn opinion ->
        %{
          quote: opinion.content,
          author: opinion.author.name
        }
      end)

    data = %{
      quotes: opinions
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end
end
