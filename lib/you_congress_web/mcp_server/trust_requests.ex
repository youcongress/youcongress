defmodule YouCongressWeb.MCPServer.TrustRequests do
  @moduledoc "Review evidence requests with authenticated moderator access."
  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response
  alias YouCongress.MCP.ToolUsageTracker

  schema do
    field :action, :string, required: true
    field :request_id, :integer
    field :status, :string
    field :resolution, :string
  end

  @impl true
  def execute(params, frame) do
    scope = if params.action == "list", do: :read, else: :write

    with {:ok, user} <- ToolUsageTracker.track(__MODULE__, frame, required_scope: scope),
         true <- user.role in ["admin", "moderator"] do
      result =
        case params.action do
          "list" ->
            Enum.map(
              YouCongress.TrustNetwork.requests(user),
              &Map.take(&1, [
                :id,
                :kind,
                :body,
                :source_url,
                :author_id,
                :statement_id,
                :status,
                :resolution,
                :attempts
              ])
            )

          "resolve" ->
            case YouCongress.TrustNetwork.resolve(
                   user,
                   params[:request_id],
                   params[:status],
                   params[:resolution]
                 ) do
              {:ok, record} -> %{id: record.id, status: record.status}
              _ -> %{error: "Invalid request or status"}
            end

          _ ->
            %{error: "Choose list or resolve"}
        end

      {:reply, Response.json(Response.tool(), result), frame}
    else
      _ ->
        {:reply, Response.error(Response.tool(), "An authorized moderator API key is required."),
         frame}
    end
  end
end
