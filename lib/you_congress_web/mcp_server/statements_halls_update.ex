defmodule YouCongressWeb.MCPServer.StatementsHallsUpdate do
  @moduledoc """
  Update the hall classification for a statement.

  Provide a `main_hall` plus any additional comma-separated tags in `other_halls`.
  This tools requires a valid API key and permission to edit the statement
  (admin or the original statement creator).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.HallsStatements
  alias YouCongress.Statements
  alias YouCongressWeb.MCPServer.StatementSerializer

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to edit this statement."
  @not_found_message "Statement not found."
  @missing_hall_message "Provide a main_hall name (e.g. 'ai') to update halls."

  schema do
    field :statement_id, :integer, required: true
    field :main_hall, :string, required: true
    field :other_halls, :string
    field :halls, :string
  end

  @impl true
  def execute(%{statement_id: statement_id} = params, frame) do
    other_input = Map.get(params, :other_halls) || Map.get(params, :halls)

    with {:ok, main_hall} <- normalize_main_hall(Map.get(params, :main_hall)),
         other_halls <- normalize_other_halls(other_input),
         {:ok, user} <- authenticate_user(frame),
         statement when not is_nil(statement) <- Statements.get_statement(statement_id),
         :ok <- ensure_permission(statement, user),
         {:ok, updated_statement} <- sync_halls(statement.id, main_hall, other_halls) do
      payload = build_payload(updated_statement, statement.id, main_hall)
      {:reply, Response.json(Response.tool(), %{statement: payload}), frame}
    else
      {:error, :missing_main_hall} ->
        {:reply, Response.error(Response.tool(), @missing_hall_message), frame}

      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}
    end
  end

  defp normalize_main_hall(hall_name) do
    case normalize_hall_name(hall_name) do
      nil -> {:error, :missing_main_hall}
      hall -> {:ok, hall}
    end
  end

  defp normalize_other_halls(nil), do: []

  defp normalize_other_halls(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,;]/, trim: true)
    |> Enum.map(&normalize_hall_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_other_halls(values) when is_list(values) do
    values
    |> Enum.map(&normalize_hall_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_other_halls(_), do: []

  defp normalize_hall_name(nil), do: nil

  defp normalize_hall_name(hall_name) do
    hall_name
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> nil
      name -> name
    end
  end

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp ensure_permission(statement, user) do
    if Permissions.can_edit_statement?(statement, user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp sync_halls(statement_id, main_hall, other_halls) do
    classification = %{
      main_tag: main_hall,
      other_tags: Enum.reject(other_halls, &(&1 == main_hall))
    }

    HallsStatements.sync!(statement_id, classification)
  rescue
    Ecto.NoResultsError ->
      {:error, :not_found}
  end

  defp build_payload(statement, statement_id, fallback_main_hall) do
    main_hall_name =
      case HallsStatements.get_main_hall(statement_id) do
        nil -> fallback_main_hall
        hall -> hall.name
      end

    %{
      statement_id: statement.id,
      title: statement.title,
      main_hall: main_hall_name,
      halls: StatementSerializer.halls(statement)
    }
  end
end
