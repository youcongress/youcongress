defmodule YouCongressWeb.MCPServer.OpinionStatementsVerify do
  @moduledoc """
  Verify that a quote (opinion) is exactly about a statement through the MCP server.

  This checks the relevance of the opinion-statement link, separately from whether
  the quote itself is authentic. The caller must provide a valid API key via the
  `?key=` query param and have permission to verify opinions.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ecto.Changeset
  alias YouCongress.Accounts.Permissions
  alias YouCongress.OpinionsStatements
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.MCP.ToolUsageTracker

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to verify opinions."
  @not_found_message "No opinion-statement link found for the given opinion_id and statement_id."
  @allowed_statuses ~w(ai_verified ai_unverifiable disputed unverifiable unverified)
  @status_aliases %{"verified" => "ai_verified"}
  @invalid_status_message "Invalid status. Allowed values: " <>
                            Enum.join(@allowed_statuses ++ Map.keys(@status_aliases), ", ")

  schema do
    field :opinion_id, :integer, required: true
    field :statement_id, :integer, required: true
    field :status, :string, required: true
    field :comment, :string, required: true
    field :model, :string, required: true
  end

  @impl true
  def execute(
        %{
          opinion_id: opinion_id,
          statement_id: statement_id,
          status: status,
          comment: comment,
          model: model
        },
        frame
      ) do
    user_result = ToolUsageTracker.track(__MODULE__, frame, required_scope: :write)

    with {:ok, normalized_status} <- normalize_status(status),
         {:ok, user} <- user_result,
         :ok <- ensure_permission(user),
         {:ok, opinion_statement} <- fetch_opinion_statement(opinion_id, statement_id),
         attrs = %{
           opinion_statement_id: opinion_statement.id,
           status: normalized_status,
           comment: comment,
           model: sanitize_model(model),
           user_id: user.id
         },
         {:ok, verification} <- OpinionStatementVerifications.create_verification(attrs) do
      data = %{
        verification: %{
          id: verification.id,
          opinion_statement_id: verification.opinion_statement_id,
          opinion_id: opinion_id,
          statement_id: statement_id,
          status: Atom.to_string(verification.status),
          comment: verification.comment,
          model: verification.model
        }
      }

      {:reply, Response.json(Response.tool(), data), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      {:error, :quote_not_verified} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Cannot verify relevance yet: the quote (opinion) must be verified or ai_verified first."
         ), frame}

      {:error, :invalid_status} ->
        {:reply, Response.error(Response.tool(), @invalid_status_message), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not create verification: #{format_changeset_errors(changeset)}"
         ), frame}
    end
  end

  defp fetch_opinion_statement(opinion_id, statement_id) do
    case OpinionsStatements.get_opinion_statement(opinion_id, statement_id) do
      nil -> {:error, :not_found}
      opinion_statement -> {:ok, opinion_statement}
    end
  end

  defp ensure_permission(user) do
    if Permissions.can_verify_opinion?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp format_changeset_errors(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(&replace_error_vars/1)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message -> "#{field} #{message}" end)
    end)
    |> Enum.join("; ")
  end

  defp replace_error_vars({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp normalize_status(status) when status in @allowed_statuses, do: {:ok, status}

  defp normalize_status(status) do
    case Map.fetch(@status_aliases, status) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, :invalid_status}
    end
  end

  defp sanitize_model("human"), do: "Unknown"
  defp sanitize_model("Human"), do: "Unknown"
  defp sanitize_model("HUMAN"), do: "Unknown"
  defp sanitize_model(model), do: model
end
