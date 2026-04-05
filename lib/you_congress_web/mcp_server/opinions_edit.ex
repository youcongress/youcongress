defmodule YouCongressWeb.MCPServer.OpinionsEdit do
  @moduledoc """
  Edit an existing opinion through the MCP server.

  The caller must provide a valid API key via the `?key=` query param and have
  permission to edit the target opinion.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ecto.Changeset
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Opinions
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to edit this opinion."
  @not_found_message "Opinion not found."
  @missing_fields_message "Provide at least one field to update: content, source_url, year, author_id."

  schema do
    field :opinion_id, :integer, required: true
    field :content, :string
    field :source_url, :string
    field :year, :integer
    field :author_id, :integer
  end

  @impl true
  def execute(%{opinion_id: opinion_id} = params, frame) do
    attrs = attrs_from_params(params)
    user_result = ToolUsageTracker.track(__MODULE__, frame)

    with :ok <- ensure_attrs_present(attrs),
         {:ok, user} <- user_result,
         opinion when not is_nil(opinion) <- Opinions.get_opinion(opinion_id),
         :ok <- ensure_permission(opinion, user),
         {:ok, _updated_opinion} <- Opinions.update_opinion(opinion, attrs),
         :ok <- maybe_update_vote_author(opinion, attrs),
         reloaded <- Opinions.get_opinion!(opinion.id) do
      data = %{opinion: take_fields(reloaded)}
      {:reply, Response.json(Response.tool(), data), frame}
    else
      {:error, :no_fields_to_update} ->
        {:reply, Response.error(Response.tool(), @missing_fields_message), frame}

      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not edit opinion: #{format_changeset_errors(changeset)}"
         ), frame}
    end
  end

  defp ensure_permission(opinion, user) do
    if Permissions.can_edit_opinion?(opinion, user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp attrs_from_params(params) do
    params
    |> Map.take([:content, :source_url, :year, :author_id])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp ensure_attrs_present(%{} = attrs) when map_size(attrs) > 0, do: :ok
  defp ensure_attrs_present(_), do: {:error, :no_fields_to_update}

  defp maybe_update_vote_author(opinion, attrs) do
    case Map.fetch(attrs, :author_id) do
      {:ok, new_author_id} when new_author_id != opinion.author_id ->
        Votes.update_author_for_opinion_votes(opinion.id, new_author_id)
        :ok

      _ ->
        :ok
    end
  end

  defp take_fields(opinion) do
    %{
      opinion_id: opinion.id,
      content: opinion.content,
      source_url: opinion.source_url,
      year: opinion.year,
      verification_status: opinion.verification_status,
      author_id: opinion.author_id,
      user_id: opinion.user_id
    }
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
