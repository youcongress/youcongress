defmodule YouCongress.Google.GoogleAPITest do
  use ExUnit.Case, async: true

  alias YouCongress.Google.GoogleAPI

  describe "generate_authorize_url/2" do
    test "returns a valid authorize URL with required parameters" do
      client_id = "test_client_id"
      callback_url = "https://example.com/callback"

      {url, state} = GoogleAPI.generate_authorize_url(client_id, callback_url)

      assert String.starts_with?(url, "https://accounts.google.com/o/oauth2/v2/auth?")
      assert String.contains?(url, "client_id=#{client_id}")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "scope=openid+email+profile")
      assert String.contains?(url, URI.encode_www_form(callback_url))
      assert String.contains?(url, "state=#{state}")
      assert String.contains?(url, "access_type=offline")
      assert String.contains?(url, "prompt=select_account")

      # State should be a non-empty string
      assert is_binary(state)
      assert byte_size(state) > 0
    end

    test "generates unique states on each call" do
      client_id = "test_client_id"
      callback_url = "https://example.com/callback"

      {_url1, state1} = GoogleAPI.generate_authorize_url(client_id, callback_url)
      {_url2, state2} = GoogleAPI.generate_authorize_url(client_id, callback_url)

      # Each call should generate unique state values
      refute state1 == state2
    end
  end
end
