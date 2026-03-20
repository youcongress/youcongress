defmodule YouCongressWeb.MCPServer.OpinionsCreate do
  @moduledoc """
  Create a new opinion through the MCP server.

  The caller must provide a valid API key using the `?key=` query param and
  have permission to speak for the provided author.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias Ecto.Changeset
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Opinions

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to create this opinion."
  @creation_failed_message "Could not create opinion:"

  schema do
    field :content, :string, required: true
    field :author_id, :integer, required: true
    field :source_url, :string
    field :year, :integer
  end

  @impl true
  def execute(%{author_id: author_id} = params, frame) do
    attrs = attrs_from_params(params)

    with {:ok, user} <- authenticate_user(frame),
         :ok <- ensure_permission(author_id, user),
         {:ok, %{opinion: opinion}} <- insert_opinion(attrs, user) do
      data = %{opinion: serialize_opinion(opinion)}
      {:reply, Response.json(Response.tool(), data), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      {:error, :opinion, %Changeset{} = changeset, _} ->
        {:reply, creation_error_response(changeset), frame}

      {:error, _operation, %Changeset{} = changeset, _changes} ->
        {:reply, creation_error_response(changeset), frame}

      {:error, _operation, _reason, _changes} ->
        {:reply,
         Response.error(
           Response.tool(),
           "#{@creation_failed_message} internal error."
         ), frame}
    end
  end

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp ensure_permission(author_id, user) do
    if Permissions.can_edit_vote?(%{author_id: author_id}, user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp insert_opinion(attrs, user) do
    attrs
    |> Map.put(:user_id, user.id)
    |> Map.put_new(:twin, false)
    |> Opinions.create_opinion()
  end

  defp attrs_from_params(params) do
    params
    |> Map.take([:content, :author_id, :source_url, :year])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp serialize_opinion(opinion) do
    %{
      opinion_id: opinion.id,
      content: opinion.content,
      source_url: opinion.source_url,
      year: opinion.year,
      author_id: opinion.author_id
    }
  end

  defp creation_error_response(%Changeset{} = changeset) do
    Response.error(
      Response.tool(),
      "#{@creation_failed_message} #{format_changeset_errors(changeset)}"
    )
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
