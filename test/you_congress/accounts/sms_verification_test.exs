defmodule YouCongress.Accounts.SmsVerificationTest do
  use ExUnit.Case, async: false

  import Mock

  alias YouCongress.Accounts.SmsVerification

  setup do
    config_keys = [:twilio_account_sid, :twilio_auth_token, :twilio_verify_service_sid]
    previous_config = Map.new(config_keys, &{&1, Application.get_env(:you_congress, &1)})

    Application.put_env(:you_congress, :twilio_account_sid, "AC-test")
    Application.put_env(:you_congress, :twilio_auth_token, "auth-test")
    Application.put_env(:you_congress, :twilio_verify_service_sid, "VA-test")

    on_exit(fn ->
      Enum.each(previous_config, fn
        {key, nil} -> Application.delete_env(:you_congress, key)
        {key, value} -> Application.put_env(:you_congress, key, value)
      end)
    end)

    :ok
  end

  describe "check_verification_code/2" do
    test "accepts only Twilio's approved status" do
      response = Jason.encode!(%{"status" => "approved", "sid" => "VE-test"})

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{}, Swoosh.Finch ->
          {:ok, %Finch.Response{status: 200, body: response}}
        end do
        assert {:ok, %{"status" => "approved"}} =
                 SmsVerification.check_verification_code("+15555550100", "123456")
      end
    end

    test "rejects a successful HTTP response whose status is pending" do
      response = Jason.encode!(%{"status" => "pending", "sid" => "VE-test"})

      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{}, Swoosh.Finch ->
          {:ok, %Finch.Response{status: 200, body: response}}
        end do
        assert {:error, "Verification code was not approved"} =
                 SmsVerification.check_verification_code("+15555550100", "000000")
      end
    end

    test "rejects a response with no verification status" do
      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{}, Swoosh.Finch ->
          {:ok, %Finch.Response{status: 200, body: ~s({"sid":"VE-test"})}}
        end do
        assert {:error, "Invalid response from verification provider"} =
                 SmsVerification.check_verification_code("+15555550100", "000000")
      end
    end

    test "rejects malformed JSON without raising" do
      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{}, Swoosh.Finch ->
          {:ok, %Finch.Response{status: 200, body: "not json"}}
        end do
        assert {:error, "Invalid response from verification provider"} =
                 SmsVerification.check_verification_code("+15555550100", "000000")
      end
    end

    test "returns provider HTTP errors" do
      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{}, Swoosh.Finch ->
          {:ok, %Finch.Response{status: 429, body: "rate limited"}}
        end do
        assert {:error, "HTTP Error 429: rate limited"} =
                 SmsVerification.check_verification_code("+15555550100", "000000")
      end
    end

    test "returns transport errors" do
      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{}, Swoosh.Finch -> {:error, :timeout} end do
        assert {:error, "Request failed: :timeout"} =
                 SmsVerification.check_verification_code("+15555550100", "000000")
      end
    end

    test "does not make a request when Twilio is not configured" do
      Application.delete_env(:you_congress, :twilio_auth_token)

      with_mock Finch, [:passthrough],
        request: fn _, _ -> flunk("unexpected Twilio request") end do
        assert {:error, "Twilio environment variables not set"} =
                 SmsVerification.check_verification_code("+15555550100", "000000")
      end
    end
  end

  describe "send_verification_code/1" do
    test "handles malformed success responses without raising" do
      with_mock Finch, [:passthrough],
        request: fn %Finch.Request{}, Swoosh.Finch ->
          {:ok, %Finch.Response{status: 201, body: "not json"}}
        end do
        assert {:error, "Invalid response from verification provider"} =
                 SmsVerification.send_verification_code("+15555550100")
      end
    end
  end
end
