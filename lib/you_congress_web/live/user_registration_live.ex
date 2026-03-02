defmodule YouCongressWeb.UserRegistrationLive do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Accounts
  alias YouCongress.Accounts.User
  alias YouCongress.Accounts.SmsVerification
  alias YouCongress.Track
  alias YouCongress.Turnstile

  @max_email_code_attempts 3
  @email_code_lock_seconds 60

  def render(assigns) do
    ~H"""
    <div id="registration-flow" class="mx-auto max-w-sm" phx-hook="SessionLogin">
      <%= if @step == :enter_email_password do %>
        <%= unless @embedded do %>
          <div class="mt-6 space-y-3">
            <.link
              href={
                if @pending_actions,
                  do: ~p"/auth/google?#{%{pending_actions: @pending_actions}}",
                  else: ~p"/auth/google"
              }
              class="w-full inline-flex justify-center items-center py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-white text-gray-700 text-sm font-medium hover:bg-gray-50"
            >
              <svg class="w-5 h-5 mr-2" viewBox="0 0 24 24">
                <path
                  fill="#4285F4"
                  d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                />
                <path
                  fill="#34A853"
                  d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                />
                <path
                  fill="#FBBC05"
                  d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                />
                <path
                  fill="#EA4335"
                  d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                />
              </svg>
              Sign up with Google
            </.link>
            <.link
              href={
                if @pending_actions,
                  do: ~p"/auth/x?#{%{pending_actions: @pending_actions}}",
                  else: ~p"/auth/x"
              }
              class="w-full inline-flex justify-center items-center py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-black text-white text-sm font-medium hover:bg-gray-800"
            >
              <svg class="w-5 h-5 mr-2" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
              </svg>
              Sign up with X
            </.link>
          </div>

          <div class="my-4">
            <div class="relative">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border-gray-300"></div>
              </div>
              <div class="relative flex justify-center text-sm">
                <span class="px-2 bg-white text-gray-500">or</span>
              </div>
            </div>
          </div>

          <.header class="text-center">
            Sign up
            <:subtitle>
              Already registered?
              <.link navigate={~p"/log_in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
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
          Enter your confirmation code
          <:subtitle>
            We sent a six-digit code to {@user.email}. Codes expire 24 hours after we send them.
          </:subtitle>
        </.header>

        <.simple_form
          for={@form}
          id="email_verification_form"
          phx-submit="verify_email"
          method="post"
        >
          <.error :if={@check_errors}>
            Oops, something went wrong! Please check the errors below.
          </.error>

          <div
            :if={email_code_locked?(@email_code_locked_until)}
            class="rounded-md bg-yellow-50 text-yellow-800 text-sm p-3"
          >
            Too many attempts. Please wait {email_code_lock_remaining(@email_code_locked_until)} seconds before trying again.
          </div>

          <.input
            field={@form[:email_verification_code]}
            type="text"
            label="6-digit code"
            placeholder="123456"
            maxlength="6"
            required
          />

          <:actions>
            <.button
              phx-disable-with="Verifying..."
              class="w-full"
              disabled={email_code_locked?(@email_code_locked_until)}
            >
              Verify email
            </.button>
          </:actions>
        </.simple_form>

        <div class="mt-4 text-center text-sm text-gray-600">
          <p>Didn't get a code? Check your spam folder or request a new one.</p>
          <.link href="#" phx-click="resend_email" class="text-blue-600 hover:underline">
            Resend code
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

    pending_actions =
      if delegate_ids != [] or map_size(votes) > 0 do
        Jason.encode!(%{delegate_ids: delegate_ids, votes: votes})
      else
        nil
      end

    socket =
      socket
      |> assign(:delegate_ids, delegate_ids)
      |> assign(:votes, votes)
      |> assign(:pending_actions, pending_actions)
      |> assign(:embedded, session["embedded"] || false)

    current_user = socket.assigns.current_user

    step =
      cond do
        current_user == nil -> :enter_email_password
        # X user without email needs to complete profile first
        current_user.email == nil -> :confirm_x_profile
        current_user.email_confirmed_at == nil -> :check_email
        # Phone verification is optional - user is done once email is confirmed
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

      changeset =
        case step do
          :check_email -> email_code_changeset()
          _ -> Accounts.change_user_registration(current_user || %User{}, initial_values)
        end

      turnstile_site_key = Application.get_env(:you_congress, :turnstile_site_key)

      socket =
        socket
        |> assign(:step, step)
        |> assign(:user, current_user)
        |> assign(:email_code_attempts, 0)
        |> assign(:email_code_locked_until, nil)
        |> assign(:session_login_sent, current_user != nil)
        |> assign(:check_errors, false)
        |> assign(:page_title, "Register for an account")
        |> assign(:turnstile_site_key, turnstile_site_key)
        |> assign_form(changeset)

      {:ok, socket, temporary_assigns: [form: nil]}
    end
  end

  def handle_event("save_email_password", params, socket) do
    turnstile_token = params["cf-turnstile-response"]
    user_params = params["user"] |> Map.take(~w(email password))
    author_params = params["user"] |> Map.take(~w(name))

    with {:turnstile, {:ok, _}} <- {:turnstile, Turnstile.verify(turnstile_token)},
         {:register, {:ok, %{user: user, author: author}}} <-
           {:register, Accounts.register_user(user_params, author_params)} do
      Track.event("Register via email/password", user)

      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )

      socket =
        socket
        |> assign(:step, :check_email)
        |> assign(:user, user)
        |> reset_email_code_state()
        |> assign_form(email_code_changeset())

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
    else
      {:turnstile, {:error, _reason}} ->
        changeset =
          %User{}
          |> Accounts.change_user_registration(params["user"] || %{})
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> put_flash(:error, "CAPTCHA verification failed. Please try again.")
         |> push_event("reset_turnstile", %{})
         |> assign_form(changeset)}

      {:register, {:error, :user, %Ecto.Changeset{} = changeset, _}} ->
        changeset = Ecto.Changeset.put_change(changeset, :name, author_params["name"])

        {:noreply,
         socket
         |> assign(check_errors: true)
         |> push_event("reset_turnstile", %{})
         |> assign_form(changeset)}

      {:register, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create author")
         |> push_event("reset_turnstile", %{})}
    end
  end

  def handle_event("verify_email", %{"user" => %{"email_verification_code" => code}}, socket) do
    user = socket.assigns.user

    if is_nil(user) do
      {:noreply, socket}
    else
      socket = maybe_unlock_email_code(socket)
      normalized_code = normalize_code(code)
      changeset = email_code_changeset(%{"email_verification_code" => normalized_code})

      cond do
        not changeset.valid? ->
          {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}

        email_code_locked?(socket.assigns.email_code_locked_until) ->
          locked_changeset =
            Ecto.Changeset.add_error(
              changeset,
              :email_verification_code,
              "Please wait before trying again."
            )

          {:noreply, socket |> assign(check_errors: true) |> assign_form(locked_changeset)}

        true ->
          case Accounts.confirm_user_with_code(user, normalized_code) do
            {:ok, updated_user} ->
              Track.event("Email verified", updated_user)

              {:noreply,
               socket
               |> assign(:user, updated_user)
               |> session_login_and_redirect(updated_user)
               |> reset_email_code_state()}

            {:error, :already_confirmed} ->
              {:noreply,
               socket
               |> session_login_and_redirect(user)
               |> reset_email_code_state()}

            {:error, :expired} ->
              expired_changeset =
                Ecto.Changeset.add_error(
                  changeset,
                  :email_verification_code,
                  "This code has expired. Request a new one and try again."
                )

              {:noreply, socket |> assign(check_errors: true) |> assign_form(expired_changeset)}

            {:error, :invalid_code} ->
              socket = increment_email_code_attempts(socket)

              message =
                if email_code_locked?(socket.assigns.email_code_locked_until) do
                  "Too many attempts. Please wait before trying again."
                else
                  "Invalid verification code"
                end

              invalid_changeset =
                Ecto.Changeset.add_error(changeset, :email_verification_code, message)

              {:noreply, socket |> assign(check_errors: true) |> assign_form(invalid_changeset)}

            {:error, _reason} ->
              generic_changeset =
                Ecto.Changeset.add_error(
                  changeset,
                  :email_verification_code,
                  "We couldn't verify that code. Please try again."
                )

              {:noreply, socket |> assign(check_errors: true) |> assign_form(generic_changeset)}
          end
      end
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
        |> reset_email_code_state()
        |> assign_form(email_code_changeset())

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
     |> reset_email_code_state()
     |> assign_form(email_code_changeset())
     |> put_flash(:info, "A new verification code has been sent to your email.")}
  end

  def handle_event("resend_phone_code", _params, socket) do
    changeset = Accounts.change_user_phone_number(socket.assigns.user)
    {:noreply, assign(socket, :step, :enter_mobile_phone) |> assign_form(changeset)}
  end

  defp session_login_and_redirect(socket, %User{} = user) do
    token = Accounts.generate_live_login_token(user)

    socket
    |> push_event("session-login", %{token: token, redirect_to: ~p"/welcome"})
    |> assign(:session_login_sent, true)
  end

  defp email_code_changeset(attrs \\ %{}) do
    {%{}, %{email_verification_code: :string}}
    |> Ecto.Changeset.cast(attrs, [:email_verification_code])
    |> Ecto.Changeset.update_change(:email_verification_code, &normalize_code/1)
    |> Ecto.Changeset.validate_required([:email_verification_code])
    |> Ecto.Changeset.validate_format(:email_verification_code, ~r/^\d{6}$/,
      message: "must be a 6-digit code"
    )
  end

  defp normalize_code(value) when is_binary(value) do
    cleaned =
      value
      |> String.replace(~r/[^0-9]/, "")
      |> String.slice(0, 6)

    cleaned || ""
  end

  defp normalize_code(_), do: ""

  defp reset_email_code_state(socket) do
    socket
    |> assign(:email_code_attempts, 0)
    |> assign(:email_code_locked_until, nil)
  end

  defp maybe_unlock_email_code(socket) do
    case socket.assigns.email_code_locked_until do
      nil ->
        socket

      locked_until ->
        if email_code_lock_remaining(locked_until) == 0 do
          assign(socket, :email_code_locked_until, nil)
        else
          socket
        end
    end
  end

  defp increment_email_code_attempts(socket) do
    attempts = socket.assigns.email_code_attempts + 1

    if attempts >= @max_email_code_attempts do
      socket
      |> assign(:email_code_attempts, 0)
      |> assign(
        :email_code_locked_until,
        DateTime.add(DateTime.utc_now(), @email_code_lock_seconds)
      )
    else
      assign(socket, :email_code_attempts, attempts)
    end
  end

  defp email_code_locked?(locked_until) do
    email_code_lock_remaining(locked_until) > 0
  end

  defp email_code_lock_remaining(nil), do: 0

  defp email_code_lock_remaining(locked_until) do
    locked_until
    |> DateTime.diff(DateTime.utc_now(), :second)
    |> max(0)
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
