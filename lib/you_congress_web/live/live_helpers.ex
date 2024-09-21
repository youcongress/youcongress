defmodule YouCongressWeb.LiveHelpers do
  @moduledoc """
  Helper functions for LiveView.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView.Socket

  @spec assign_current_user(Socket.t(), binary) :: Socket.t()
  def assign_current_user(socket, nil), do: assign(socket, :current_user, nil)

  def assign_current_user(socket, user_token) do
    current_user = YouCongress.Accounts.get_user_by_session_token(user_token)
    assign(socket, :current_user, current_user)
  end
end
