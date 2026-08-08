defmodule YouCongressWeb.Plugs.AiBasicAuth do
  @moduledoc """
  Hides the AI policy pages behind HTTP Basic Auth while they're unlaunched.

  Credentials come from AI_BASIC_AUTH_USERNAME/AI_BASIC_AUTH_PASSWORD. When they
  are missing the pages stay closed in production and open everywhere else, so
  dev and test don't need to set them.
  """
  import Plug.Conn

  @realm "AI Working Groups"

  def init(opts), do: opts

  def call(conn, _opts) do
    config = Application.get_env(:you_congress, :ai_basic_auth) || []

    case {config[:username], config[:password]} do
      {username, password}
      when is_binary(username) and is_binary(password) and
             username != "" and password != "" ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password, realm: @realm)

      _ ->
        if Application.get_env(:you_congress, :env) == :prod do
          conn
          |> Plug.BasicAuth.request_basic_auth(realm: @realm)
          |> halt()
        else
          conn
        end
    end
  end
end
