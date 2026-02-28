defmodule YouCongressWeb.MCPServer.StatementsCreate do
  @moduledoc """
  Create new statements (policy proposals and claims) through the MCP server.

  The caller must provide a valid API key via the `?key=` query param and own a role
  that passes `YouCongress.Accounts.Permissions.can_create_statement?/1`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias Ecto.Changeset
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Statements

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @forbidden_message "Your account is not allowed to create statements."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."

  schema do
    field :title, :string, required: true
  end

  @impl true
  def execute(%{title: title}, frame) do
    with {:ok, user} <- authenticate_user(frame),
         :ok <- ensure_permission(user),
         {:ok, statement} <- insert_statement(title, user) do
      {:reply, build_success(statement), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, error_response(@missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, error_response(@invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, error_response(@forbidden_message), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         error_response("Could not create statement: #{format_changeset_errors(changeset)}"),
         frame}
    end
  end

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp ensure_permission(user) do
    if Permissions.can_create_statement?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp insert_statement(title, user) do
    %{"title" => title, "user_id" => user.id}
    |> Statements.create_statement()
  end

  defp build_success(statement) do
    data = %{
      statement_id: statement.id,
      title: statement.title,
      slug: statement.slug,
      url: "/p/#{statement.slug}"
    }

    Response.json(Response.tool(), data)
  end

  defp error_response(message) when is_binary(message) do
    Response.error(Response.tool(), message)
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
end
