defmodule YouCongress.PendingActions do
  @moduledoc """
  Stores actions collected before authentication and applies them only after
  the user has proved control of their email address.
  """

  import Ecto.Query

  alias YouCongress.Accounts.User
  alias YouCongress.PendingActions.PendingRegistrationAction
  alias YouCongress.Reconsiderations
  alias YouCongress.Repo

  @valid_for_seconds 24 * 60 * 60

  def process(%User{} = user, nil), do: maybe_process_staged(user)

  def process(%User{} = user, pending_json) when is_binary(pending_json) do
    with {:ok, payload} <- Jason.decode(pending_json) do
      process(user, payload)
    else
      _ -> {:error, :invalid_pending_actions}
    end
  end

  def process(%User{} = user, payload) when is_map(payload) do
    with :ok <- validate_payload(payload),
         {:ok, _pending_action} <- stage(user, payload) do
      maybe_process_staged(user)
    end
  end

  def process(%User{}, _payload), do: {:error, :invalid_pending_actions}

  @doc "Applies and deletes a user's unexpired staged action after email confirmation."
  def process_staged(%User{id: user_id}) do
    Repo.transaction(fn ->
      user = Repo.get!(User, user_id)

      pending_action =
        PendingRegistrationAction
        |> where([action], action.user_id == ^user_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      process_locked(user, pending_action)
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp stage(%User{} = user, payload) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    timestamp = DateTime.to_naive(now)
    expires_at = DateTime.add(now, @valid_for_seconds, :second)

    %PendingRegistrationAction{}
    |> PendingRegistrationAction.changeset(%{
      user_id: user.id,
      payload: payload,
      expires_at: expires_at
    })
    |> Repo.insert(
      on_conflict: [set: [payload: payload, expires_at: expires_at, updated_at: timestamp]],
      conflict_target: [:user_id],
      returning: true
    )
  end

  defp maybe_process_staged(%User{email_confirmed_at: nil}), do: :ok
  defp maybe_process_staged(%User{} = user), do: process_staged(user)

  defp process_locked(_user, nil), do: :ok

  defp process_locked(%User{email_confirmed_at: nil}, _pending_action), do: :ok

  defp process_locked(user, %PendingRegistrationAction{} = pending_action) do
    if DateTime.compare(pending_action.expires_at, DateTime.utc_now()) == :gt do
      case process_payload(user, pending_action.payload) do
        :ok ->
          Repo.delete!(pending_action)
          :ok

        {:error, reason} ->
          Repo.rollback(reason)
      end
    else
      Repo.delete!(pending_action)
      :ok
    end
  end

  defp validate_payload(%{"reconsideration" => reconsideration}) when is_map(reconsideration),
    do: :ok

  defp validate_payload(%{"delegate_ids" => delegate_ids, "votes" => votes})
       when is_list(delegate_ids) and is_map(votes),
       do: :ok

  defp validate_payload(_payload), do: {:error, :invalid_pending_actions}

  defp process_payload(user, %{"reconsideration" => reconsideration}) do
    case Reconsiderations.submit_pending(user, reconsideration) do
      {:ok, _responses} -> :ok
      {:error, :already_submitted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_payload(user, %{"delegate_ids" => delegate_ids, "votes" => votes}) do
    with :ok <- create_delegations(user, delegate_ids),
         :ok <- create_votes(user, votes),
         do: :ok
  end

  defp process_payload(_user, _payload), do: {:error, :invalid_pending_actions}

  defp create_delegations(user, delegate_ids) do
    Enum.reduce_while(delegate_ids, :ok, fn delegate_id, :ok ->
      result =
        if YouCongress.Delegations.delegating?(user.author_id, delegate_id) do
          :ok
        else
          case YouCongress.Delegations.create_delegation(user, delegate_id) do
            {:ok, _delegation} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp create_votes(user, votes) do
    Enum.reduce_while(votes, :ok, fn {_statement_id, vote_data}, :ok ->
      case create_pending_vote(user, vote_data) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp create_pending_vote(user, %{"answer" => answer} = vote_data)
       when answer in ["for", "against", "abstain"] do
    case YouCongress.Votes.create_or_update(%{
           statement_id: vote_data["statement_id"],
           answer: String.to_existing_atom(answer),
           author_id: user.author_id,
           user_id: user.id,
           direct: true
         }) do
      {:ok, _vote} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_pending_vote(_user, %{"answer" => answer}) when answer in [nil, ""], do: :ok
  defp create_pending_vote(_user, _vote_data), do: {:error, :invalid_pending_vote}
end
