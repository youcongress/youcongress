defmodule YouCongressWeb.ReturnTo do
  @moduledoc """
  Helpers for carrying local return paths through authentication flows.
  """

  @blocked_paths ["/log_in", "/log_out", "/sign_up", "/welcome"]

  def sanitize(nil), do: nil

  def sanitize(return_to) when is_binary(return_to) do
    return_to = String.trim(return_to)

    with false <- return_to == "",
         false <- String.starts_with?(return_to, "//"),
         false <- String.contains?(return_to, "\\"),
         %URI{scheme: nil, host: nil} = uri <- URI.parse(return_to),
         path when is_binary(path) <- uri.path,
         true <- String.starts_with?(path, "/"),
         false <- path in @blocked_paths do
      %URI{path: path, query: uri.query}
      |> URI.to_string()
    else
      _ -> nil
    end
  rescue
    URI.Error -> nil
  end

  def sanitize(_), do: nil

  def from_url(url) when is_binary(url) do
    uri = URI.parse(url)
    sanitize(URI.to_string(%URI{path: uri.path || "/", query: uri.query}))
  rescue
    URI.Error -> nil
  end

  def from_url(_), do: nil

  def from_same_origin_url(url, host) when is_binary(url) and is_binary(host) do
    uri = URI.parse(url)

    if same_origin?(uri, host) do
      sanitize(URI.to_string(%URI{path: uri.path || "/", query: uri.query}))
    end
  rescue
    URI.Error -> nil
  end

  def from_same_origin_url(_, _), do: nil

  def welcome_path(return_to) do
    path_with_query("/welcome", return_to: sanitize(return_to))
  end

  def sign_up_path(return_to, pending_actions \\ nil) do
    path_with_query("/sign_up", pending_actions: pending_actions, return_to: sanitize(return_to))
  end

  def log_in_path(pending_actions \\ nil, return_to \\ nil) do
    path_with_query("/log_in", pending_actions: pending_actions, return_to: sanitize(return_to))
  end

  def auth_path(provider, pending_actions \\ nil, return_to \\ nil)

  def auth_path(:google, pending_actions, return_to) do
    path_with_query("/auth/google",
      pending_actions: pending_actions,
      return_to: sanitize(return_to)
    )
  end

  def auth_path(:x, pending_actions, return_to) do
    path_with_query("/auth/x", pending_actions: pending_actions, return_to: sanitize(return_to))
  end

  defp path_with_query(path, params) do
    params =
      Enum.reject(params, fn {_key, value} ->
        is_nil(value) or value == ""
      end)

    case URI.encode_query(params) do
      "" -> path
      query -> "#{path}?#{query}"
    end
  end

  defp same_origin?(%URI{host: nil}, _host), do: true

  defp same_origin?(%URI{host: url_host}, host) do
    String.downcase(url_host) == String.downcase(host)
  end
end
