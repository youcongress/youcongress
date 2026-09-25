defmodule YouCongressWeb.MagicLinkLive do
  use YouCongressWeb, :live_view

  alias YouCongressWeb.ReturnTo

  def render(assigns) do
    ~H"""
    <div class="mx-auto mt-12 max-w-sm text-center">
      <.header>
        Continue to YouCongress
        <:subtitle>
          Use the button below to finish signing in. This link can only be used once.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="magic_link_confirmation_form"
        action={~p"/log_in/magic-link/#{@token}"}
        class="mt-6"
      >
        <input :if={@return_to} type="hidden" name="return_to" value={@return_to} />
        <input
          :if={@pending_actions}
          type="hidden"
          name="pending_actions"
          value={@pending_actions}
        />
        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full bg-indigo-500 hover:bg-indigo-700">
            Sign in
          </.button>
        </:actions>
      </.simple_form>

      <p class="mt-4 text-sm text-gray-600">
        Didn't request this? You can safely close this page.
      </p>
    </div>
    """
  end

  def mount(%{"token" => token} = params, _session, socket) do
    {:ok,
     assign(socket,
       token: token,
       return_to: ReturnTo.sanitize(params["return_to"]),
       pending_actions: params["pending_actions"],
       form: to_form(%{}, as: "magic_link")
     )}
  end
end
