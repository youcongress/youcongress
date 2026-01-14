defmodule YouCongress.X.XAPITest do
  use ExUnit.Case, async: true

  alias YouCongress.X.XAPI

  describe "generate_authorize_url/2" do
    test "returns a valid authorize URL with required parameters" do
      client_id = "test_client_id"
      callback_url = "https://example.com/callback"

      {url, code_verifier, state} = XAPI.generate_authorize_url(client_id, callback_url)

      assert String.starts_with?(url, "https://twitter.com/i/oauth2/authorize?")
      assert String.contains?(url, "client_id=#{client_id}")
      assert String.contains?(url, "response_type=code")
      assert String.contains?(url, "scope=users.read+users.email.read+tweet.read")
      assert String.contains?(url, "code_challenge_method=S256")
      assert String.contains?(url, URI.encode_www_form(callback_url))
      assert String.contains?(url, "state=#{state}")

      # Code verifier should be a non-empty string
      assert is_binary(code_verifier)
      assert byte_size(code_verifier) > 0

      # State should be a non-empty string
      assert is_binary(state)
      assert byte_size(state) > 0
    end

    test "generates unique code verifiers and states on each call" do
      client_id = "test_client_id"
      callback_url = "https://example.com/callback"

      {_url1, code_verifier1, state1} = XAPI.generate_authorize_url(client_id, callback_url)
      {_url2, code_verifier2, state2} = XAPI.generate_authorize_url(client_id, callback_url)

      # Each call should generate unique values
      refute code_verifier1 == code_verifier2
      refute state1 == state2
    end
  end
end
