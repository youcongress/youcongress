defmodule YouCongressWeb.MCPServer.StatementsShow do
  @moduledoc """
  Return a single statement along with its halls and participating authors.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements
  alias YouCongressWeb.MCPServer.StatementSerializer

  @not_found_message "Statement not found."

  schema do
    field :statement_id, :integer, required: true
  end

  @impl true
  def execute(%{statement_id: statement_id}, frame) do
    case fetch_statement(statement_id) do
      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      statement ->
        data = %{statement: serialize_statement(statement)}
        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp fetch_statement(statement_id) do
    Statements.get_statement(statement_id,
      preload: [
        :halls,
        opinions: [:author]
      ]
    )
  end

  defp serialize_statement(statement) do
    %{
      statement_id: statement.id,
      title: statement.title,
      halls: StatementSerializer.halls(statement),
      authors: serialize_authors(statement)
    }
  end

  defp serialize_authors(%{opinions: opinions}) when is_list(opinions) do
    opinions
    |> Enum.map(& &1.author)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn author, acc ->
      Map.put_new(acc, author.id, author)
    end)
    |> Map.values()
    |> Enum.sort_by(&String.downcase(&1.name || ""))
    |> Enum.map(fn author ->
      %{
        author_id: author.id,
        name: author.name,
        bio: author.bio,
        country: author.country,
        twitter_username: author.twitter_username
      }
    end)
  end

  defp serialize_authors(_), do: []
end
