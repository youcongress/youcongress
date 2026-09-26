defmodule YouCongressWeb.NewsletterLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Newsletters
  alias YouCongress.RateLimiter
  alias YouCongress.Turnstile

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    confirmed? = params["confirmed"] == "true"

    form_attrs =
      case socket.assigns.current_user do
        nil -> %{}
        current_user -> %{email: current_user.email}
      end

    {:ok,
     socket
     |> assign(:page_title, "Subscribe to YouCongress news")
     |> assign(:requested?, confirmed?)
     |> assign(:confirmed?, confirmed?)
     |> assign(:turnstile_site_key, Application.get_env(:you_congress, :turnstile_site_key))
     |> assign_form(Newsletters.change_request(form_attrs))}
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

      <.link
        :if={!@requested? && @current_user && @current_user.newsletter}
        navigate={~p"/explore"}
        class="mt-4 inline-flex w-full items-center justify-center rounded-md bg-indigo-600 px-4 py-2 font-semibold text-white hover:bg-indigo-500"
      >
        Explore
      </.link>

      <.simple_form
        :if={!@requested? && (is_nil(@current_user) || !@current_user.newsletter)}
        for={@form}
        id="newsletter-form"
        phx-submit="subscribe"
        phx-change="validate"
      >
        <.input field={@form[:email]} type="email" label="Email" required />
        <div
          :if={@turnstile_site_key && is_nil(@current_user)}
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

  def handle_event("subscribe", %{"user" => params} = event_params, socket) do
    changeset = Newsletters.change_request(params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, %{email: email}} ->
        subscribe(socket, email, event_params)

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp subscribe(%{assigns: %{current_user: current_user}} = socket, email, _event_params)
       when not is_nil(current_user) do
    if same_email?(email, current_user.email) do
      subscribe_current_user(socket, current_user)
    else
      request_subscription(socket, email, "subscribe_page_authenticated", current_user)
    end
  end

  defp subscribe(socket, email, event_params) do
    with {:turnstile, {:ok, _}} <-
           {:turnstile, Turnstile.verify(event_params["cf-turnstile-response"])} do
      request_subscription(socket, email, "subscribe_page_anonymous", nil)
    else
      {:turnstile, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "CAPTCHA verification failed. Please try again.")
         |> push_event("reset_turnstile", %{})}
    end
  end

  defp subscribe_current_user(socket, current_user) do
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

  defp request_subscription(socket, email, source, current_user) do
    with {:rate_limit, true} <-
           {:rate_limit, RateLimiter.allowed?(:newsletter_confirmation, email, 3, 60 * 60)},
         {:global_limit, true} <-
           {:global_limit,
            RateLimiter.allowed?(:newsletter_confirmation_global, :global, 10_000, 24 * 60 * 60)},
         {:request, {:ok, _consent}} <-
           {:request, Newsletters.request_subscription(%{email: email}, source, current_user)} do
      {:noreply, assign(socket, :requested?, true)}
    else
      {:request, {:error, changeset}} ->
        {:noreply, assign_form(socket, %{changeset | action: :validate})}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Please wait before requesting another email.")
         |> push_event("reset_turnstile", %{})}
    end
  end

  defp same_email?(left, right), do: String.downcase(left) == String.downcase(right)

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "user"))
end
