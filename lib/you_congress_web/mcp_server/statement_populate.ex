defmodule YouCongressWeb.MCPServer.StatementPopulate do
  @moduledoc """
  Trigger AI-assisted quote discovery for a statement.

  This tool requires an admin API key. It queues the same background job that the
  product UI uses when an authorized user clicks "Find quotes".
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements
  alias YouCongress.Workers.QuotatorWorker
  alias YouCongress.MCP.ToolUsageTracker

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Only administrators can trigger automated quote discovery."
  @not_found_message "Statement not found."
  @job_failed_message "Unable to start AI quote discovery. Please try again later."

  schema do
    field :statement_id, :integer, required: true
  end

  @impl true
  def execute(%{statement_id: statement_id}, frame) do
    user_result = ToolUsageTracker.track(__MODULE__, frame)

    with {:ok, user} <- user_result,
         :ok <- ensure_admin(user),
         {:ok, statement} <- fetch_statement(statement_id),
         :ok <- enqueue_quote_job(statement.id, user.id) do
      payload = %{
        statement_id: statement.id,
        title: statement.title,
        status: "quote_generation_started",
        message: "Queued AI job to populate quotes for this statement."
      }

      {:reply, Response.json(Response.tool(), payload), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      {:error, :job_failed} ->
        {:reply, Response.error(Response.tool(), @job_failed_message), frame}
    end
  end

  defp ensure_admin(%{role: "admin"}), do: :ok
  defp ensure_admin(_), do: {:error, :forbidden}

  defp fetch_statement(statement_id) do
    case Statements.get_statement(statement_id) do
      nil -> {:error, :not_found}
      statement -> {:ok, statement}
    end
  end

  defp enqueue_quote_job(statement_id, user_id) do
    %{statement_id: statement_id, user_id: user_id}
    |> QuotatorWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, _changeset} -> {:error, :job_failed}
    end
  end
end
