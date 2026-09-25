defmodule YouCongress.Accounts.SmsVerification do
  @moduledoc """
  Handles SMS verification functionality using Twilio's Verify service.
  """

  def send_verification_code(phone_number) do
    with {:ok, {twilio_account_sid, twilio_auth_token, twilio_verify_service_sid}} <-
           twilio_config() do
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
          decode_response(body)

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "HTTP Error #{status}: #{body}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  def check_verification_code(phone_number, code) do
    with {:ok, {twilio_account_sid, twilio_auth_token, twilio_verify_service_sid}} <-
           twilio_config() do
      twilio_api_url =
        "https://verify.twilio.com/v2/Services/#{twilio_verify_service_sid}/VerificationCheck"

      headers = [
        {"Authorization",
         "Basic " <> Base.encode64("#{twilio_account_sid}:#{twilio_auth_token}")},
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
          case Jason.decode(body) do
            {:ok, %{"status" => "approved"} = response} -> {:ok, response}
            {:ok, %{"status" => _status}} -> {:error, "Verification code was not approved"}
            {:ok, _response} -> {:error, "Invalid response from verification provider"}
            {:error, _reason} -> {:error, "Invalid response from verification provider"}
          end

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "HTTP Error #{status}: #{body}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  defp twilio_config do
    config =
      {
        Application.get_env(:you_congress, :twilio_account_sid),
        Application.get_env(:you_congress, :twilio_auth_token),
        Application.get_env(:you_congress, :twilio_verify_service_sid)
      }

    case config do
      {account_sid, auth_token, service_sid}
      when is_binary(account_sid) and byte_size(account_sid) > 0 and is_binary(auth_token) and
             byte_size(auth_token) > 0 and is_binary(service_sid) and byte_size(service_sid) > 0 ->
        {:ok, config}

      _ ->
        {:error, "Twilio environment variables not set"}
    end
  end

  defp decode_response(body) do
    case Jason.decode(body) do
      {:ok, response} -> {:ok, response}
      {:error, _reason} -> {:error, "Invalid response from verification provider"}
    end
  end
end
