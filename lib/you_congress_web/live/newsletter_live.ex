defmodule YouCongressWeb.NewsletterLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Newsletters
  alias YouCongress.RateLimiter
  alias YouCongress.Turnstile

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    confirmed? = params["confirmed"] == "true"

    {:ok,
     socket
     |> assign(:page_title, "Subscribe to YouCongress news")
     |> assign(:requested?, confirmed?)
     |> assign(:confirmed?, confirmed?)
     |> assign(:turnstile_site_key, Application.get_env(:you_congress, :turnstile_site_key))
     |> assign_form(Newsletters.change_request())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Subscribe to YouCongress news
        <:subtitle>AI governance, safety, jobs, and product updates.</:subtitle>
      </.header>

      <div :if={@confirmed?} class="mt-6 rounded-md bg-green-50 p-4 text-green-900">
        Your newsletter subscription is confirmed.
      </div>

      <div :if={@requested? && !@confirmed?} class="mt-6 rounded-md bg-blue-50 p-4 text-blue-900">
        Check your email and open the confirmation link to subscribe.
      </div>

      <div
        :if={!@requested? && @current_user && @current_user.newsletter}
        class="mt-6 rounded-md bg-green-50 p-4 text-green-900"
      >
        You are already subscribed.
      </div>

      <button
        :if={!@requested? && @current_user && !@current_user.newsletter}
        type="button"
        phx-click="subscribe"
        class="mt-6 w-full rounded-md bg-indigo-600 px-4 py-2 font-semibold text-white"
      >
        Subscribe
      </button>

      <.simple_form
        :if={!@requested? && !@current_user}
        for={@form}
        id="newsletter-form"
        phx-submit="subscribe"
        phx-change="validate"
      >
        <.input field={@form[:email]} type="email" label="Email" required />
        <div
          :if={@turnstile_site_key}
          id="turnstile-widget"
          phx-hook="Turnstile"
          data-sitekey={@turnstile_site_key}
          phx-update="ignore"
          class="mt-4"
        >
        </div>
        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">Subscribe</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = params |> Newsletters.change_request() |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("subscribe", _params, %{assigns: %{current_user: current_user}} = socket)
      when not is_nil(current_user) do
    case Newsletters.subscribe_user(current_user, "subscribe_page_authenticated") do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, %{user | author: current_user.author})
         |> assign(:confirmed?, true)
         |> assign(:requested?, true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "We could not update your subscription.")}
    end
  end

  def handle_event("subscribe", %{"user" => params} = event_params, socket) do
    changeset = Newsletters.change_request(params)

    with {:validation, {:ok, %{email: email}}} <-
           {:validation, Ecto.Changeset.apply_action(changeset, :insert)},
         {:turnstile, {:ok, _}} <-
           {:turnstile, Turnstile.verify(event_params["cf-turnstile-response"])},
         {:rate_limit, true} <-
           {:rate_limit, RateLimiter.allowed?(:newsletter_confirmation, email, 3, 60 * 60)},
         {:global_limit, true} <-
           {:global_limit,
            RateLimiter.allowed?(:newsletter_confirmation_global, :global, 10_000, 24 * 60 * 60)},
         {:request, {:ok, _consent}} <-
           {:request,
            Newsletters.request_subscription(%{email: email}, "subscribe_page_anonymous")} do
      {:noreply, assign(socket, :requested?, true)}
    else
      {:validation, {:error, changeset}} ->
        {:noreply, assign_form(socket, changeset)}

      {:request, {:error, changeset}} ->
        {:noreply, assign_form(socket, %{changeset | action: :validate})}

      {:turnstile, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "CAPTCHA verification failed. Please try again.")
         |> push_event("reset_turnstile", %{})}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Please wait before requesting another email.")
         |> push_event("reset_turnstile", %{})}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "user"))
end
