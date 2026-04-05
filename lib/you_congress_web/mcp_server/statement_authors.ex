defmodule YouCongressWeb.MCPServer.StatementAuthors do
  @moduledoc """
  List every author that already has at least one sourced quote (opinion with a
  non-nil source URL) attached to a statement.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ecto.Association.NotLoaded
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements
  alias YouCongress.MCP.ToolUsageTracker

  @statement_not_found_message "Statement not found."

  schema do
    field :statement_id, :integer, required: true
  end

  @impl true
  def execute(%{statement_id: statement_id}, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    case Statements.get_statement(statement_id) do
      nil ->
        {:reply, Response.error(Response.tool(), @statement_not_found_message), frame}

      statement ->
        authors =
          statement.id
          |> fetch_statement_quotes()
          |> serialize_authors()

        data = %{
          statement_id: statement.id,
          statement_title: statement.title,
          authors: authors
        }

        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp fetch_statement_quotes(statement_id) do
    Opinions.list_opinions(
      statement_ids: [statement_id],
      only_quotes: true,
      preload: :author,
      order_by: [asc: :author_id, desc: :inserted_at]
    )
  end

  defp serialize_authors(opinions) do
    opinions
    |> Enum.reject(&missing_author?/1)
    |> Enum.reduce(%{}, fn opinion, acc ->
      author = opinion.author

      Map.put_new(acc, author.id, %{
        author_id: author.id,
        name: author.name,
        opinion_year: opinion.year
      })
    end)
    |> Map.values()
    |> Enum.sort_by(&String.downcase(&1.name || ""))
  end

  defp missing_author?(%Opinion{author_id: nil}), do: true
  defp missing_author?(%Opinion{author: nil}), do: true
  defp missing_author?(%Opinion{author: %NotLoaded{}}), do: true
  defp missing_author?(%Opinion{}), do: false
  defp missing_author?(_), do: true
end
