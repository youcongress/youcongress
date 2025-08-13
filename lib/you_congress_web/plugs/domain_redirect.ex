defmodule YouCongressWeb.Plugs.DomainRedirect do
  @moduledoc """
  Redirects requests from alternative domains to the canonical domain.

  Redirects:
  - www.youcongress.org -> youcongress.org
  - youcongress.com -> youcongress.org
  - www.youcongress.com -> youcongress.org
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    host = get_req_header(conn, "host") |> List.first()
    canonical_host = "youcongress.org"

    case host do
      "www.youcongress.org" -> redirect_to_canonical(conn, canonical_host)
      "youcongress.com" -> redirect_to_canonical(conn, canonical_host)
      "www.youcongress.com" -> redirect_to_canonical(conn, canonical_host)
      _ -> conn
    end
  end

  defp redirect_to_canonical(conn, canonical_host) do
    url = build_canonical_url(conn, canonical_host)

    conn
    |> put_resp_header("location", url)
    |> resp(301, "")
    |> halt()
  end

  defp build_canonical_url(conn, canonical_host) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    path_and_query = full_path(conn)

    "#{scheme}://#{canonical_host}#{path_and_query}"
  end

  defp full_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      query_string -> "#{conn.request_path}?#{query_string}"
    end
  end
end
