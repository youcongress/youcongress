defmodule YouCongress.Accounts.SmsVerification do
  @moduledoc """
  Handles SMS verification functionality using Twilio's Verify service.
  """

  def send_verification_code(phone_number) do
    twilio_account_sid = Application.get_env(:you_congress, :twilio_account_sid)
    twilio_auth_token = Application.get_env(:you_congress, :twilio_auth_token)
    twilio_verify_service_sid = Application.get_env(:you_congress, :twilio_verify_service_sid)

    if twilio_account_sid && twilio_auth_token && twilio_verify_service_sid do
      twilio_api_url =
        "https://verify.twilio.com/v2/Services/#{twilio_verify_service_sid}/Verifications"

      headers = [
        {"Authorization",
         "Basic " <> Base.encode64("#{twilio_account_sid}:#{twilio_auth_token}")},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

      body =
        URI.encode_query(%{
          "To" => phone_number,
          "Channel" => "sms"
        })

      request = Finch.build(:post, twilio_api_url, headers, body)

      case Finch.request(request, Swoosh.Finch) do
        {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, Jason.decode!(body)}

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "HTTP Error #{status}: #{body}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    else
      {:error, "Twilio environment variables not set"}
    end
  end

  def check_verification_code(phone_number, code) do
    twilio_account_sid = Application.get_env(:you_congress, :twilio_account_sid)
    twilio_auth_token = Application.get_env(:you_congress, :twilio_auth_token)
    twilio_verify_service_sid = Application.get_env(:you_congress, :twilio_verify_service_sid)

    twilio_api_url =
      "https://verify.twilio.com/v2/Services/#{twilio_verify_service_sid}/VerificationCheck"

    headers = [
      {"Authorization", "Basic " <> Base.encode64("#{twilio_account_sid}:#{twilio_auth_token}")},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    body =
      URI.encode_query(%{
        "To" => phone_number,
        "Code" => code
      })

    request = Finch.build(:post, twilio_api_url, headers, body)

    case Finch.request(request, Swoosh.Finch) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, "HTTP Error #{status}: #{body}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end
end
