defmodule YouCongress.Accounts.UserNotifier do
  @moduledoc """
  The UserNotifier module.
  """

  import Swoosh.Email

  require Logger

  alias YouCongress.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"YouCongress", "hello@youcongress.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      Logger.debug(email)
      {:ok, email}
    end
  end

  def deliver_test do
    deliver(
      "hec@hecperez.com",
      "Test email",
      "Whatever"
    )
  end

  def deliver_email_verification_instructions(email, code) do
    deliver(email, "Email verification code", """
    Hi #{email},

    Your code to verify your email is:

    #{code}

    Best regards,
    Hector
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """
    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
