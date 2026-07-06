defmodule YouCongressWeb.MCPServer.AuthorsList do
  @moduledoc """
  List authors on YouCongress.
  Returns up to 100 authors ordered by id ("desc" by default, newest first, or "asc").
  Pass the last_id from a previous response to get the next page.
  Pass country (name or ISO code) to only list authors from that country.
  Pass without_country: true to only list authors with no country set.
  By default, authors from all countries (including those without a country) are listed.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Authors
  alias YouCongress.Countries
  alias YouCongressWeb.MCPServer.ListPagination
  alias YouCongress.MCP.ToolUsageTracker

  schema do
    field :last_id, :integer
    field :order, :string, default: "desc"
    field :country, :string
    field :without_country, :boolean, default: false
  end

  @limit 100

  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    case country_filter(params) do
      {:error, country} ->
        {:reply, Response.error(Response.tool(), "Unknown country: #{country}"), frame}

      {:ok, country_opts} ->
        authors =
          ([limit: @limit, order_by: order_by(params)] ++ country_opts)
          |> ListPagination.maybe_paginate(params)
          |> Authors.list_authors()
          |> Authors.preload([:country])

        data = %{
          authors: Enum.map(authors, &take_fields/1),
          last_id: ListPagination.last_id(authors)
        }

        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp country_filter(%{without_country: true}), do: {:ok, [country_id: nil]}

  defp country_filter(%{country: country}) when is_binary(country) and country != "" do
    case Countries.get_country_by_name_or_iso(country) do
      nil -> {:error, country}
      country -> {:ok, [country_id: country.id]}
    end
  end

  defp country_filter(_params), do: {:ok, []}

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
