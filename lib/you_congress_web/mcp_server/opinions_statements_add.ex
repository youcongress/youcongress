defmodule YouCongressWeb.MCPServer.OpinionsStatementsAdd do
  @moduledoc """
  Attach an existing opinion to a statement through the MCP server.

  The caller must supply a valid API key via the `?key=` query param and have
  permission to manage statement opinions.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias Ecto.Changeset
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Opinions
  alias YouCongress.Statements
  alias YouCongress.Votes

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to attach opinions to statements."
  @opinion_not_found "Opinion not found."
  @statement_not_found "Statement not found."
  @already_linked "Opinion is already associated with this statement."
  @vote_answer_options ["For", "Abstain", "Against"]
  @invalid_vote_answer_message "Answer must be one of: #{Enum.join(@vote_answer_options, ", ")}."
  @vote_answer_lookup %{"for" => :for, "against" => :against, "abstain" => :abstain}

  schema do
    field :opinion_id, :integer, required: true
    field :statement_id, :integer, required: true
    field :vote_answer, :string, required: true
  end

  @impl true
  def execute(
        %{opinion_id: opinion_id, statement_id: statement_id, vote_answer: vote_answer},
        frame
      ) do
    with {:ok, normalized_vote_answer} <- normalize_vote_answer(vote_answer),
         {:ok, user} <- authenticate_user(frame),
         :ok <- ensure_permission(user),
         {:ok, opinion} <- fetch_opinion(opinion_id),
         {:ok, statement} <- fetch_statement(statement_id),
         {:ok, _} <- Opinions.add_opinion_to_statement(opinion, statement, user.id),
         {:ok, vote} <- upsert_vote(opinion, statement, normalized_vote_answer) do
      data = %{
        opinion_id: opinion.id,
        statement_id: statement.id,
        statement_title: statement.title,
        statement_slug: statement.slug,
        attached: true,
        vote: %{
          vote_id: vote.id,
          statement_id: vote.statement_id,
          author_id: vote.author_id,
          answer: vote.answer && Atom.to_string(vote.answer)
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

      {:error, :opinion_not_found} ->
        {:reply, Response.error(Response.tool(), @opinion_not_found), frame}

      {:error, :statement_not_found} ->
        {:reply, Response.error(Response.tool(), @statement_not_found), frame}

      {:error, :already_associated} ->
        {:reply, Response.error(Response.tool(), @already_linked), frame}

      {:error, :invalid_vote_answer} ->
        {:reply, Response.error(Response.tool(), @invalid_vote_answer_message), frame}

      {:error, :user_id_required} ->
        {:reply,
         Response.error(Response.tool(), "A valid user is required to attach the opinion."),
         frame}

      {:error, :transaction_failed} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not attach opinion to statement due to an internal error."
         ), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not attach opinion to statement: #{format_changeset_errors(changeset)}"
         ), frame}
    end
  end

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp ensure_permission(user) do
    if Permissions.can_add_opinion_to_statement?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp fetch_opinion(opinion_id) do
    case Opinions.get_opinion(opinion_id) do
      nil -> {:error, :opinion_not_found}
      opinion -> {:ok, opinion}
    end
  end

  defp fetch_statement(statement_id) do
    case Statements.get_statement(statement_id) do
      nil -> {:error, :statement_not_found}
      statement -> {:ok, statement}
    end
  end

  defp normalize_vote_answer(answer) when is_binary(answer) do
    answer
    |> String.trim()
    |> String.downcase()
    |> case do
      normalized ->
        case Map.fetch(@vote_answer_lookup, normalized) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, :invalid_vote_answer}
        end
    end
  end

  defp normalize_vote_answer(answer) when is_atom(answer) do
    answer
    |> Atom.to_string()
    |> normalize_vote_answer()
  end

  defp normalize_vote_answer(_), do: {:error, :invalid_vote_answer}

  defp upsert_vote(opinion, statement, vote_answer) do
    attrs = %{
      author_id: opinion.author_id,
      statement_id: statement.id,
      opinion_id: opinion.id,
      answer: vote_answer,
      direct: true
    }

    case Votes.get_by(%{statement_id: statement.id, author_id: opinion.author_id}) do
      nil ->
        Votes.create_vote(attrs)

      vote ->
        update_attrs = Map.take(attrs, [:answer, :direct, :opinion_id])
        Votes.update_vote(vote, update_attrs)
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
end
