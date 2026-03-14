defmodule YouCongressWeb.MCPServer.VotesEdit do
  @moduledoc """
  Edit an existing vote through the MCP server.
  answer must be one of: for, against, or abstain

  The caller must provide a valid API key via the `?key=` query param and have
  permission to edit the target vote.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias Ecto.Changeset
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Votes

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to edit this vote."
  @not_found_message "Vote not found."
  @missing_fields_message "Provide at least one field to update: answer."

  schema do
    field :statement_id, :integer, required: true
    field :author_id, :integer, required: true
    field :answer, :string
  end

  @impl true
  def execute(%{statement_id: statement_id, author_id: author_id} = params, frame) do
    attrs = attrs_from_params(params)

    with :ok <- ensure_attrs_present(attrs),
         {:ok, user} <- authenticate_user(frame),
         vote when not is_nil(vote) <-
           Votes.get_by(%{statement_id: statement_id, author_id: author_id}, preload: [:opinion]),
         :ok <- ensure_permission(vote, user),
         :ok <- ensure_vote_editable_by_user(vote, user),
         {:ok, updated_vote} <- Votes.update_vote(vote, attrs) do
      data = %{vote: take_fields(updated_vote)}
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
           "Could not edit vote: #{format_changeset_errors(changeset)}"
         ), frame}
    end
  end

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp ensure_permission(vote, user) do
    if Permissions.can_edit_vote?(vote, user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp ensure_vote_editable_by_user(%{opinion: nil}, _user), do: :ok

  defp ensure_vote_editable_by_user(%{opinion: opinion}, user) do
    case user_vote_owner_id(opinion) do
      nil -> :ok
      owner_id when owner_id == user.id -> :ok
      _ -> {:error, :forbidden}
    end
  end

  defp user_vote_owner_id(nil), do: nil

  defp user_vote_owner_id(opinion) do
    Map.get(opinion, :user_id) || Map.get(opinion, :source_id)
  end

  defp attrs_from_params(params) do
    params
    |> Map.take([:answer])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp ensure_attrs_present(%{} = attrs) when map_size(attrs) > 0, do: :ok
  defp ensure_attrs_present(_), do: {:error, :no_fields_to_update}

  defp take_fields(vote) do
    %{
      vote_id: vote.id,
      statement_id: vote.statement_id,
      author_id: vote.author_id,
      answer: vote.answer && Atom.to_string(vote.answer),
      direct: vote.direct,
      twin: vote.twin,
      opinion_id: vote.opinion_id
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
