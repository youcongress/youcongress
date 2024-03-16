defmodule YouCongressWeb.LiveHelpers do
  @moduledoc """
  Helper functions for LiveView.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Phoenix.LiveView.Socket

  @spec assign_current_user(Socket.t(), binary) :: Socket.t()
  def assign_current_user(socket, nil), do: assign(socket, :current_user, nil)

  def assign_current_user(socket, user_token) do
    current_user = YouCongress.Accounts.get_user_by_session_token(user_token)
    assign(socket, :current_user, current_user)
  end

  @spec assign_counters(Socket.t()) :: Socket.t()
  def assign_counters(socket) do
    assign(socket,
      votes_count: YouCongress.Votes.count(),
      user_votes_count: get_user_votes_count(socket.assigns.current_user)
    )
  end

  @spec get_user_votes_count(integer | nil) :: integer | nil
  defp get_user_votes_count(nil), do: nil

  defp get_user_votes_count(%{author_id: id}) do
    YouCongress.Votes.count_by_author_id(id)
  end
end
