defmodule YouCongressWeb.WelcomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Accounts
  alias YouCongress.Accounts.User
  alias YouCongress.Track

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    changeset = User.welcome_changeset(socket.assigns.current_user, %{})

    if connected?(socket) do
      %{assigns: %{current_user: current_user}} = socket
      Track.event("View Welcome", current_user)
    end

    {:ok, assign_form(socket, changeset)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Welcome")
    |> assign(:statement, nil)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.welcome_update(socket.assigns.current_user, user_params) do
      {:ok, _} ->
        {:noreply, redirect(socket, to: ~p"/")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply, redirect(socket, to: ~p"/?search=#{query}&tab=quotes")}
  end

  @impl true
end
