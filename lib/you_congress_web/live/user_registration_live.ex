defmodule YouCongressWeb.UserRegistrationLive do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Accounts
  alias YouCongress.Accounts.User
  alias YouCongress.Accounts.SmsVerification
  alias YouCongress.Track

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <%= if @step == :enter_email_password do %>
        <%= unless @embedded do %>
          <.header class="text-center">
            <:subtitle>
              Already registered?
              <.link navigate={~p"/log_in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>

          <.header class="text-center pt-6">
            Register for an account
          </.header>
        <% end %>
        <.simple_form
          for={@form}
          id="registration_form"
          phx-submit="save_email_password"
          phx-change="validate"
          method="post"
        >
          <.error :if={@check_errors}>
            Oops, something went wrong! Please check the errors below.
          </.error>

          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:password]} type="password" label="Password" required />

          <:actions>
            <.button phx-disable-with="Creating account..." class="w-full">Create Account</.button>
          </:actions>
        </.simple_form>
      <% end %>

      <%= if @step == :check_email do %>
        <.header class="text-center">
          Please check your email & spam folder
          <:subtitle>
            We've sent you instructions to validate your email
          </:subtitle>
        </.header>

        <div class="mt-4 text-center">
          <.link href="#" phx-click="resend_email" class="text-sm text-blue-600 hover:underline">
            Resend email
          </.link>
        </div>
      <% end %>

      <%= if @step == :enter_mobile_phone do %>
        <.header class="text-center text-xs">
          Enter your mobile phone number
          <:subtitle>
            This verification helps us mitigate spam and abuse.
          </:subtitle>
        </.header>

        <.simple_form
          for={@form}
          id="phone_form"
          phx-submit="save_phone_number"
          phx-change="validate"
          method="post"
        >
          <.error :if={@check_errors}>
            Please enter a valid phone number.
          </.error>

          <.input
            field={@form[:phone_number]}
            type="tel"
            label="Mobile phone number with country code"
            placeholder="+1 555 555 5555"
            required
          />

          <:actions>
            <.button phx-disable-with="Sending code..." class="w-full">
              Send Verification Code
            </.button>
          </:actions>
        </.simple_form>

        <div class="mt-4 text-center">
          <.link navigate={~p"/welcome"} class="text-sm text-gray-600 hover:text-gray-800 underline">
            Skip for now
          </.link>
        </div>
      <% end %>

      <%= if @step == :validate_phone do %>
        <.header class="text-center">
          Verify your phone number
          <:subtitle>
            We've sent a code to {@user.phone_number}
          </:subtitle>
        </.header>

        <.simple_form
          for={@form}
          id="phone_verification_form"
          phx-submit="verify_phone"
          phx-change="validate"
          method="post"
        >
          <.error :if={@check_errors}>
            Oops, something went wrong! Please check the errors below.
          </.error>

          <.input
            field={@form[:phone_verification_code]}
            type="text"
            label="Code"
            placeholder="XXXXXX"
            required
          />

          <:actions>
            <.button phx-disable-with="Verifying..." class="w-full">
              Verify and Complete Registration
            </.button>
          </:actions>
        </.simple_form>

        <div class="mt-4 text-center">
          <.link href="#" phx-click="resend_phone_code" class="text-sm text-blue-600 hover:underline">
            Change phone number or/and resend code
          </.link>
          <span class="mx-2 text-gray-400">|</span>
          <.link navigate={~p"/welcome"} class="text-sm text-gray-600 hover:text-gray-800 underline">
            Skip for now
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    delegate_ids = session["delegate_ids"] || []
    votes = session["votes"] || %{}

    socket =
      socket
      |> assign(:delegate_ids, delegate_ids)
      |> assign(:votes, votes)
      |> assign(:embedded, session["embedded"] || false)

    current_user = socket.assigns.current_user

    step =
      cond do
        current_user == nil -> :enter_email_password
        current_user.email_confirmed_at == nil -> :validate_email
        current_user.phone_number == nil -> :enter_mobile_phone
        current_user.phone_number_confirmed_at == nil -> :enter_mobile_phone
        true -> :done
      end

    if step == :done do
      {:ok, redirect(socket, to: ~p"/welcome")}
    else
      changeset = Accounts.change_user_registration(current_user || %User{})

      socket =
        socket
        |> assign(:step, step)
        |> assign(:user, current_user)
        |> assign(:check_errors, false)
        |> assign(:page_title, "Register for an account")
        |> assign_form(changeset)

      {:ok, socket, temporary_assigns: [form: nil]}
    end
  end

  def handle_event("save_email_password", %{"user" => params}, socket) do
    user_params = Map.take(params, ~w(email password))
    author_params = Map.take(params, ~w(name))

    case Accounts.register_user(user_params, author_params) do
      {:ok, %{user: user, author: author}} ->
        Track.event("Register via email/password", user)

        Accounts.deliver_user_confirmation_instructions(
          user,
          &url(~p"/users/confirm/#{&1}")
        )

        socket =
          socket
          |> assign(:step, :check_email)
          |> assign(:user, user)

        # Pending Actions
        if socket.assigns.delegate_ids != [] do
          for id <- socket.assigns.delegate_ids do
            YouCongress.Delegations.create_delegation(user, id)
          end
        end

        if map_size(socket.assigns.votes) > 0 do
          for {_voting_id, vote_data} <- socket.assigns.votes do
            YouCongress.Votes.create_or_update(%{
              voting_id: vote_data.voting_id,
              answer: vote_data.answer,
              author_id: author.id,
              direct: true
            })
          end
        end

        {:noreply, socket}

      {:error, :user, %Ecto.Changeset{} = changeset, _} ->
        changeset = Ecto.Changeset.put_change(changeset, :name, author_params["name"])
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}

      _ ->
        {:error, put_flash(socket, :error, "Failed to create author")}
    end
  end

  def handle_event("verify_email", %{"user" => %{"email_verification_code" => code}}, socket) do
    user = socket.assigns.user

    if code == socket.assigns.email_code do
      case Accounts.confirm_user_email(user) do
        {:ok, _user} ->
          Track.event("Email verified", user)

          changeset = Accounts.change_user_phone_number(user)
          {:noreply, socket |> assign(step: :enter_mobile_phone) |> assign_form(changeset)}

        {:error, changeset} ->
          {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
      end
    else
      changeset =
        user
        |> Accounts.change_user_registration()
        |> Ecto.Changeset.add_error(:email_verification_code, "Invalid verification code")

      {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("save_phone_number", %{"user" => %{"phone_number" => phone_number}}, socket) do
    phone_number = String.replace(phone_number, ~r/\s|\(|\)/, "")

    with {:ok, user} <-
           Accounts.update_user_phone_number(socket.assigns.user, phone_number),
         {:ok, _} <- SmsVerification.send_verification_code(phone_number) do
      Track.event("Phone number saved", user)

      changeset =
        Accounts.change_user_phone_number(user, %{"phone_number" => phone_number})

      socket =
        socket
        |> assign(:step, :validate_phone)
        |> assign(:user, user)
        |> assign_form(changeset)

      {:noreply, socket}
    else
      error ->
        Logger.error("Failed to send verification code: #{inspect(error)}")

        changeset =
          socket.assigns.user
          |> Accounts.change_user_phone_number(%{phone_number: phone_number})
          |> Ecto.Changeset.add_error(
            :phone_number,
            "Failed to send verification code. Please try again later."
          )

        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("verify_phone", %{"user" => %{"phone_verification_code" => code}}, socket) do
    user = socket.assigns.user

    case SmsVerification.check_verification_code(user.phone_number, code) do
      {:ok, _response} ->
        case Accounts.confirm_user_phone(user) do
          {:ok, _} ->
            Track.event("Phone number verified", user)
            {:noreply, redirect(socket, to: ~p"/welcome")}

          {:error, changeset} ->
            {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
        end

      {:error, reason} ->
        changeset =
          user
          |> Accounts.change_user_phone_number(%{phone_number: user.phone_number})
          |> Ecto.Changeset.add_error(
            :phone_verification_code,
            "Invalid verification code: #{reason}"
          )

        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("resend_email", _params, socket) do
    user = socket.assigns.user

    Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))

    {:noreply,
     socket
     |> put_flash(:info, "A new verification URL has been sent to your email.")}
  end

  def handle_event("resend_phone_code", _params, socket) do
    changeset = Accounts.change_user_phone_number(socket.assigns.user)
    {:noreply, assign(socket, :step, :enter_mobile_phone) |> assign_form(changeset)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
