defmodule YouCongressWeb.ContactLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Contact
  alias YouCongress.Turnstile

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-xl px-4 py-8 sm:px-6">
      <.header class="text-center">
        Contact us
        <:subtitle>Send a message to the YouCongress team.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="contact-form"
        phx-change="validate"
        phx-submit="send"
        class="mt-6"
      >
        <.input field={@form[:name]} type="text" label="Name" autocomplete="name" required />
        <.input field={@form[:email]} type="email" label="Email" autocomplete="email" required />
        <.input
          field={@form[:website]}
          type="url"
          label="Your website or social media link (optional)"
          placeholder="https://"
        />
        <.input field={@form[:subject]} type="text" label="Subject" required />
        <.input field={@form[:body]} type="textarea" label="Message" rows="8" required />

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
          <.button phx-disable-with="Sending..." class="w-full">Send message</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    attrs = %{
      "name" => current_user && current_user.author && current_user.author.name,
      "email" => current_user && current_user.email,
      "subject" => params["subject"],
      "body" => params["body"]
    }

    {:ok,
     socket
     |> assign(:page_title, "Contact us")
     |> assign(:turnstile_site_key, Application.get_env(:you_congress, :turnstile_site_key))
     |> assign_form(Contact.changeset(%Contact{}, attrs))}
  end

  @impl true
  def handle_event("validate", %{"contact" => params}, socket) do
    changeset =
      %Contact{}
      |> Contact.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("send", %{"contact" => params} = event_params, socket) do
    changeset = Contact.changeset(%Contact{}, params)

    with {:contact, {:ok, contact}} <- {:contact, Ecto.Changeset.apply_action(changeset, :insert)},
         {:turnstile, {:ok, _}} <-
           {:turnstile, Turnstile.verify(event_params["cf-turnstile-response"])},
         {:delivery, {:ok, _}} <- {:delivery, Contact.deliver(contact)} do
      {:noreply,
       socket
       |> put_flash(:info, "Your message has been sent.")
       |> push_event("reset_turnstile", %{})
       |> assign_form(Contact.changeset(%Contact{}))}
    else
      {:contact, {:error, changeset}} ->
        {:noreply, assign_form(socket, changeset)}

      {:turnstile, {:error, _reason}} ->
        {:noreply,
         socket
         |> put_flash(:error, "CAPTCHA verification failed. Please try again.")
         |> push_event("reset_turnstile", %{})
         |> assign_form(Map.put(changeset, :action, :validate))}

      {:delivery, {:error, _reason}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Your message could not be sent. Please try again.")
         |> push_event("reset_turnstile", %{})
         |> assign_form(Map.put(changeset, :action, :validate))}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "contact"))
  end
end
