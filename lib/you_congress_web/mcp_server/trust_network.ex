defmodule YouCongressWeb.MCPServer.TrustNetwork do
  @moduledoc "Read named public people lists, admin-only YouCongress Trust 30, and recommendations. Private Councils are never exposed."
  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response

  schema do
    field :view, :string, required: true
    field :author_id, :integer
    field :scope, :string
    field :community, :integer
    field :nominators, :string
    field :nominees, :string
  end

  @impl true
  def execute(params, frame) do
    data =
      case params.view do
        "rankings" ->
          rankings(frame)

        "communities" ->
          []

        "council" ->
          %{error: "Councils are private. Use lists to read public people lists."}

        "lists" ->
          public_lists(params[:author_id])

        "recommendations" ->
          if params[:author_id],
            do:
              Enum.map(YouCongress.TrustNetwork.recommendations(params.author_id), fn row ->
                Map.take(row.record, [:nominee_id, :scope, :reason, :source_url])
                |> Map.put(:name, row.name)
              end),
            else: %{error: "author_id required"}

        _ ->
          %{error: "Choose rankings, lists, or recommendations"}
      end

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp rankings(frame) do
    with {:ok, user} <-
           YouCongress.MCP.ToolUsageTracker.track(__MODULE__, frame, required_scope: :read),
         true <- YouCongress.Accounts.admin?(user) do
      YouCongress.Councils.Discovery.trust30()
    else
      _ -> %{error: "Trust List rankings are currently available to admins only."}
    end
  end

  defp public_lists(nil), do: %{error: "author_id required"}

  defp public_lists(id) do
    Enum.map(YouCongress.PeopleLists.for_author(id), fn list ->
      %{
        id: list.id,
        name: list.name,
        author_id: list.author_id,
        members: Enum.map(list.members, &Map.take(&1, [:author_id, :reason]))
      }
    end)
  end
end
