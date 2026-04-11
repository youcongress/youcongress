defmodule YouCongressWeb.PageController do
  use YouCongressWeb, :controller

  alias YouCongress.FeatureFlags
  alias YouCongress.Statements

  def terms(conn, _params) do
    render(conn, :terms)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy)
  end

  def sitemap(conn, _params) do
    statements = Statements.list_statements(order: :updated_at_desc)
    body = build_sitemap(statements)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  defp build_sitemap(statements) do
    urls =
      Enum.map(statements, fn statement ->
        lastmod =
          (statement.updated_at || statement.inserted_at)
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        loc = url(~p"/p/#{statement.slug}")

        """
          <url>
            <loc>#{loc}</loc>
            <lastmod>#{lastmod}</lastmod>
            <changefreq>weekly</changefreq>
            <priority>0.6</priority>
          </url>
        """
      end)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      urls,
      ~s(</urlset>\n)
    ]
  end

  def waiting_list(conn, _params) do
    render(conn, :waiting_list, layout: false)
  end

  def about(conn, _params) do
    render(conn, :about,
      search: nil,
      search_tab: :quotes,
      halls: [],
      authors: [],
      statements: [],
      quotes: [],
      log_in_with_x_enabled: FeatureFlags.enabled?(:log_in_with_x)
    )
  end

  def faq(conn, _params) do
    render(conn, :faq)
  end

  def mcp_tools(conn, _params) do
    render(conn, :mcp_tools)
  end

  def mcp_claude(conn, _params) do
    render(conn, :mcp_claude)
  end

  def redirect_to_questions(conn, _params) do
    conn
    |> redirect(to: ~p"/")
    |> halt()
  end

  def redirect_to_home(conn, _params) do
    conn
    |> redirect(to: ~p"/")
    |> halt()
  end

  def email_login_waiting_list(conn, _params) do
    render(conn, :email_login_waiting_list, layout: false)
  end

  def email_login_waiting_list_thanks(conn, _params) do
    conn
    |> put_flash(:info, "Thanks for joining the waiting list! We'll be in touch.")
    |> redirect(to: ~p"/")
  end
end
