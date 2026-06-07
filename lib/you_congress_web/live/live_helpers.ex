defmodule YouCongressWeb.LiveHelpers do
  @moduledoc """
  Helper functions for LiveView.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView.Socket
  alias YouCongressWeb.ReturnTo

  @spec assign_current_user(Socket.t(), binary) :: Socket.t()
  def assign_current_user(socket, nil), do: assign(socket, :current_user, nil)

  def assign_current_user(socket, user_token) do
    current_user = YouCongress.Accounts.get_user_by_session_token(user_token)
    assign(socket, :current_user, current_user)
  end

  @doc """
  Stores a guest vote attempt so we can prompt for authentication and replay it later.
  """
  @spec record_guest_vote(Socket.t(), map()) :: Socket.t()
  def record_guest_vote(socket, payload) do
    votes = socket.assigns[:pending_guest_votes] || %{}

    statement_id = payload[:statement_id]
    statement_title = payload[:statement_title]
    normalized_answer = normalize_answer(payload[:answer])

    vote = %{
      statement_id: statement_id,
      answer: vote_answer_to_atom(normalized_answer)
    }

    return_to =
      payload[:return_to] ||
        socket.assigns[:vote_auth_return_to] ||
        socket.assigns[:return_to]

    socket
    |> assign(:pending_guest_votes, Map.put(votes, statement_id, vote))
    |> assign(:pending_vote_prompt, %{statement_title: statement_title, answer: normalized_answer})
    |> assign(:vote_auth_return_to, ReturnTo.sanitize(return_to))
    |> assign(:show_vote_auth_modal, true)
  end

  defp normalize_answer(answer) do
    answer
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp vote_answer_to_atom("for"), do: :for
  defp vote_answer_to_atom("against"), do: :against
  defp vote_answer_to_atom("abstain"), do: :abstain
  defp vote_answer_to_atom(other), do: String.to_existing_atom(other)
end
