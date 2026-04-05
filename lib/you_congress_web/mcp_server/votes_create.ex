defmodule YouCongressWeb.MCPServer.VotesCreate do
  @moduledoc """
  Create a new vote through the MCP server.

  The caller must provide a valid API key via the `?key=` query param and have
  permission to create a vote for the provided author.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ecto.Changeset
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Votes
  alias YouCongress.MCP.ToolUsageTracker

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to create this vote."
  @duplicate_vote_message "This author already has a vote for the selected statement."

  schema do
    field :statement_id, :integer, required: true
    field :author_id, :integer, required: true
    field :answer, :string, required: true
    field :opinion_id, :integer
  end

  @impl true
  def execute(%{author_id: author_id, statement_id: statement_id} = params, frame) do
    attrs = attrs_from_params(params)
    user_result = ToolUsageTracker.track(__MODULE__, frame)

    with {:ok, user} <- user_result,
         :ok <- ensure_permission(author_id, user),
         :ok <- ensure_vote_absent(statement_id, author_id),
         {:ok, vote} <- Votes.create_vote(attrs) do
      data = %{vote: take_fields(vote)}
      {:reply, Response.json(Response.tool(), data), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      {:error, :duplicate_vote} ->
        {:reply, Response.error(Response.tool(), @duplicate_vote_message), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not create vote: #{format_changeset_errors(changeset)}"
         ), frame}
    end
  end

  defp ensure_permission(author_id, user) do
    if Permissions.can_edit_vote?(%{author_id: author_id}, user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp attrs_from_params(params) do
    params
    |> Map.take([:statement_id, :author_id, :answer, :opinion_id])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> Map.put_new(:direct, true)
    |> Map.put_new(:twin, false)
  end

  defp ensure_vote_absent(statement_id, author_id) do
    case Votes.get_by(%{statement_id: statement_id, author_id: author_id}) do
      nil -> :ok
      _vote -> {:error, :duplicate_vote}
    end
  end

  defp take_fields(vote) do
    %{
      vote_id: vote.id,
      statement_id: vote.statement_id,
      author_id: vote.author_id,
      answer: vote.answer && Atom.to_string(vote.answer),
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
