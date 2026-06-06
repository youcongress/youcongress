defmodule YouCongressWeb.MCPServer.AuthorsList do
  @moduledoc """
  List authors on YouCongress.
  Returns up to 100 authors ordered by id ("desc" by default — newest first, or "asc").
  Pass the last_id from a previous response to get the next page.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Authors
  alias YouCongressWeb.MCPServer.ListPagination
  alias YouCongress.MCP.ToolUsageTracker

  schema do
    field :last_id, :integer
    field :order, :string, default: "desc"
  end

  @limit 100

  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    authors =
      [limit: @limit, order_by: order_by(params)]
      |> ListPagination.maybe_paginate(params)
      |> Authors.list_authors()
      |> Authors.preload([:country])

    data = %{
      authors: Enum.map(authors, &take_fields/1),
      last_id: ListPagination.last_id(authors)
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp order_by(params) do
    case ListPagination.order(params) do
      :asc -> [asc: :id]
      :desc -> [desc: :id]
    end
  end

  defp take_fields(author) do
    %{
      author_id: author.id,
      name: author.name,
      bio: author.bio,
      wikipedia_url: author.wikipedia_url,
      twitter_username: author.twitter_username,
      country_id: author.country_id,
      country: Authors.country_name(author)
    }
  end
end
