defmodule YouCongress.PendingActions do
  @moduledoc """
  Applies votes, delegations, and Reconsider submissions collected before authentication.
  """

  alias YouCongress.Accounts.User
  alias YouCongress.Reconsiderations

  def process(%User{}, nil), do: :ok

  def process(%User{} = user, pending_json) when is_binary(pending_json) do
    case Jason.decode(pending_json) do
      {:ok, payload} -> process_payload(user, payload)
      _ -> {:error, :invalid_pending_actions}
    end
  end

  def process(%User{} = user, payload) when is_map(payload), do: process_payload(user, payload)

  defp process_payload(user, %{"reconsideration" => reconsideration}) do
    case Reconsiderations.submit_pending(user, reconsideration) do
      {:ok, _responses} -> :ok
      {:error, :already_submitted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_payload(user, %{"delegate_ids" => delegate_ids, "votes" => votes}) do
    Enum.each(delegate_ids, fn id ->
      unless YouCongress.Delegations.delegating?(user.author_id, id) do
        YouCongress.Delegations.create_delegation(user, id)
      end
    end)

    Enum.each(votes, fn {_statement_id, vote_data} ->
      if vote_data["answer"] && vote_data["answer"] != "" do
        create_pending_vote(user, vote_data)
      end
    end)

    :ok
  end

  defp process_payload(_user, _payload), do: {:error, :invalid_pending_actions}

  defp create_pending_vote(user, vote_data) do
    YouCongress.Votes.create_or_update(%{
      statement_id: vote_data["statement_id"],
      answer: String.to_existing_atom(vote_data["answer"]),
      author_id: user.author_id,
      user_id: user.id,
      direct: true
    })
  rescue
    _ -> :ok
  end
end
