defmodule YouCongressWeb.MCPServer.AuthorsSearch do
  @moduledoc """
  Search authors in YouCongress.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Authors

  @limit 50

  schema do
    field :query, :string, required: true
  end

  @impl true
  def execute(%{query: query}, frame) do
    matches = query |> search_authors()

    data = %{matches: matches}

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp search_authors(query) do
    [search: query]
    |> Authors.list_authors()
    |> Enum.take(@limit)
    |> Enum.map(&take_fields/1)
  end

  defp take_fields(author) do
    %{
      author_id: author.id,
      name: author.name,
      bio: author.bio,
      wikipedia_url: author.wikipedia_url,
      twitter_username: author.twitter_username,
      country: author.country
    }
  end
end
