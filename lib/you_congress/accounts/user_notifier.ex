defmodule YouCongress.Accounts.UserNotifier do
  @moduledoc """
  The UserNotifier module.
  """

  import Swoosh.Email
  import Plug.HTML, only: [html_escape: 1]

  require Logger

  alias YouCongress.Mailer
  alias YouCongress.Accounts.User
  alias YouCongressWeb.Endpoint

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, text_body_content, html_body_content) do
    email =
      new()
      |> to(recipient)
      |> from({"YouCongress", "hello@youcongress.org"})
      |> subject(subject)
      |> text_body(text_body_content)
      |> html_body(html_body_content)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      Logger.debug(email)
      {:ok, email}
    end
  end

  def deliver_test do
    deliver(
      "hec@hecperez.com",
      "Test email",
      "Whatever",
      build_html_email("Test email", ["Whatever"], nil, nil)
    )
  end

  defp build_html_email(title, paragraphs, button_label, button_url) do
    paragraph_markup =
      paragraphs
      |> Enum.map(fn paragraph ->
        text = html_escape_text(paragraph)

        "<p style=\"margin: 0 0 16px; font-size: 15px; line-height: 1.6; color: #0f172a;\">#{text}</p>"
      end)
      |> Enum.join("\n")

    button_markup =
      case {button_label, button_url} do
        {label, url} when is_binary(label) and is_binary(url) ->
          safe_label = html_escape_text(label)
          safe_url = html_escape_text(url)

          """
          <div style=\"text-align: center; margin: 32px 0;\">
            <a
              href=\"#{safe_url}\"
              style=\"display: inline-block; padding: 14px 28px; background-color: #0f172a; color: #ffffff; text-decoration: none; border-radius: 9999px; font-weight: 600; font-size: 15px;\"
            >#{safe_label}</a>
          </div>
          """

        _ ->
          ""
      end

    safe_title = html_escape_text(title)

    """
    <!DOCTYPE html>
    <html>
      <body style=\"margin: 0; padding: 24px; background-color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;\">
        <div style=\"max-width: 520px; margin: 0 auto; background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 16px; padding: 32px; box-shadow: 0 15px 45px rgba(15, 23, 42, 0.08);\">
          <p style=\"margin: 0 0 24px; font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; color: #94a3b8;\">YouCongress</p>
          <h1 style=\"margin: 0 0 24px; font-size: 22px; color: #0f172a;\">#{safe_title}</h1>
          #{paragraph_markup}
          #{button_markup}
          <p style=\"margin: 32px 0 0; font-size: 13px; color: #64748b;\">— The YouCongress Team</p>
        </div>
        <p style=\"max-width: 520px; margin: 18px auto 0; text-align: center; font-size: 12px; color: #94a3b8;\">
          © #{Date.utc_today().year} YouCongress. All rights reserved.
        </p>
      </body>
    </html>
    """
  end

  defp html_escape_text(text) do
    text
    |> to_string()
    |> html_escape()
    |> IO.iodata_to_binary()
  end

  @doc """
  Deliver notification when quote finding process completes.
  """
  def deliver_quotes_found_notification(nil, _statement_title, _statement_slug, _num_quotes),
    do: {:ok, :no_email}

  def deliver_quotes_found_notification(email, statement_title, statement_slug, num_quotes) do
    statement_url = "#{Endpoint.url()}/p/#{statement_slug}"
    pluralized_quote = if num_quotes == 1, do: "quote", else: "quotes"

    text_body = """
    Hi,

    The quote search for \"#{statement_title}\" is complete.

    #{num_quotes} #{pluralized_quote} #{if num_quotes == 1, do: "was", else: "were"} added to the statement.

    Visit YouCongress to read them: #{statement_url}
    """

    html_body =
      build_html_email(
        "Quotes found for \"#{statement_title}\"",
        [
          "The quote search for \"#{statement_title}\" just wrapped up.",
          "#{num_quotes} #{pluralized_quote} #{if num_quotes == 1, do: "was", else: "were"} added to your statement."
        ],
        "Read the quotes",
        statement_url
      )

    deliver(email, "Quotes found for \"#{statement_title}\"", text_body, html_body)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(%User{} = user, code) do
    text_body = """
    Hi #{user.email},

    Your six-digit YouCongress confirmation code is: #{code}

    Enter this code on the sign-up page within 24 hours to verify your email. If you didn't create an account with us, you can safely ignore this email.
    """

    html_body =
      build_html_email(
        "Confirm your email",
        [
          "Thanks for signing up for YouCongress.",
          "Enter the six-digit code below on the sign-up screen within 24 hours to confirm your email address.",
          "Confirmation code: #{code}"
        ],
        nil,
        nil
      )

    deliver(user.email, "Confirmation instructions", text_body, html_body)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    text_body = """
    Hi #{user.email},

    You can reset your password by visiting the link below:

    #{url}

    If you didn't request this change, please ignore this.
    """

    html_body =
      build_html_email(
        "Reset your password",
        [
          "We received a request to reset the password for #{user.email}.",
          "Click the button below to create a new password. This link expires shortly for your security."
        ],
        "Reset password",
        url
      )

    deliver(user.email, "Reset password instructions", text_body, html_body)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    text_body = """
    Hi #{user.email},

    You can update your email address by visiting the link below:

    #{url}

    If you didn't request this change, please ignore this.
    """

    html_body =
      build_html_email(
        "Update your email",
        [
          "You recently told us you'd like to use a different email address for YouCongress.",
          "Hit the button below to confirm that change."
        ],
        "Update email",
        url
      )

    deliver(user.email, "Update email instructions", text_body, html_body)
  end
end
