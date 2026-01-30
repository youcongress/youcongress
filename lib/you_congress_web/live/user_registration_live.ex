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

          <div class="mt-6">
            <.link
              href={~p"/auth/x"}
              class="w-full inline-flex justify-center items-center py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-black text-white text-sm font-medium hover:bg-gray-800"
            >
              <svg class="w-5 h-5 mr-2" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
              </svg>
              Sign up with X
            </.link>
          </div>

          <div class="my-6">
            <div class="relative">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border-gray-300"></div>
              </div>
              <div class="relative flex justify-center text-sm">
                <span class="px-2 bg-white text-gray-500">Or register with email</span>
              </div>
            </div>
          </div>
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

      <%= if @step == :confirm_x_profile do %>
        <.header class="text-center">
          Complete Your Profile
          <:subtitle>
            Please confirm your name and add your email address
          </:subtitle>
        </.header>

        <.simple_form
          for={@form}
          id="x_profile_form"
          phx-submit="save_x_profile"
          phx-change="validate_x_profile"
          method="post"
        >
          <.error :if={@check_errors}>
            Oops, something went wrong! Please check the errors below.
          </.error>

          <.input field={@form[:name]} type="text" label="Name" required />
          <.input field={@form[:email]} type="email" label="Email" required />

          <:actions>
            <.button phx-disable-with="Saving..." class="w-full">Continue</.button>
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
        # X user without email needs to complete profile first
        current_user.email == nil -> :confirm_x_profile
        current_user.email_confirmed_at == nil -> :check_email
        current_user.phone_number == nil -> :enter_mobile_phone
        current_user.phone_number_confirmed_at == nil -> :enter_mobile_phone
        true -> :done
      end

    if step == :done do
      {:ok, redirect(socket, to: ~p"/welcome")}
    else
      # For X users, preload their name from the author
      initial_values =
        if step == :confirm_x_profile && current_user.author do
          %{name: current_user.author.name}
        else
          %{}
        end

      changeset = Accounts.change_user_registration(current_user || %User{}, initial_values)

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
          Enum.each(socket.assigns.votes, fn {_statement_id, vote_data} ->
            YouCongress.Votes.create_or_update(%{
              statement_id: vote_data.statement_id,
              answer: vote_data.answer,
              author_id: author.id,
              direct: true
            })
          end)
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

  def handle_event("validate_x_profile", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save_x_profile", %{"user" => params}, socket) do
    user = socket.assigns.user
    email = params["email"]
    name = params["name"]

    with {:ok, user} <- Accounts.update_x_user_email(user, email),
         {:ok, _author} <- YouCongress.Authors.update_author(user.author, %{name: name}) do
      Track.event("X profile completed", user)

      Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))

      socket =
        socket
        |> assign(:step, :check_email)
        |> assign(:user, user)

      {:noreply, socket}
    else
      {:error, changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
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
