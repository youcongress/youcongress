defmodule YouCongressWeb.NewsletterConfirmationLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Newsletters

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Confirm newsletter subscription")
     |> assign(:token, token)
     |> assign(:confirmed?, false)
     |> assign(:invalid?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm text-center">
      <.header>
        Confirm newsletter subscription
        <:subtitle>Please confirm that you want to receive YouCongress updates.</:subtitle>
      </.header>

      <div :if={@confirmed?} class="mt-6 rounded-md bg-green-50 p-4 text-green-900">
        Your newsletter subscription is confirmed.
      </div>

      <div :if={@invalid?} class="mt-6 rounded-md bg-red-50 p-4 text-red-900">
        This newsletter confirmation link is invalid or has expired.
      </div>

      <button
        :if={!@confirmed? && !@invalid?}
        type="button"
        phx-click="confirm"
        class="mt-6 w-full rounded-md bg-indigo-600 px-4 py-2 font-semibold text-white"
      >
        Confirm subscription
      </button>
    </div>
    """
  end

  @impl true
  def handle_event("confirm", _params, socket) do
    case Newsletters.confirm_subscription(socket.assigns.token) do
      {:ok, _consent} ->
        {:noreply, assign(socket, confirmed?: true, token: nil)}

      {:error, :invalid_or_expired_token} ->
        {:noreply, assign(socket, invalid?: true, token: nil)}
    end
  end
end
