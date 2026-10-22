defmodule YouCongressWeb.PageControllerSecurityTest do
  use YouCongressWeb.ConnCase

  import Mock
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures

  test "sitemap escapes XML metacharacters without changing the decoded URL", %{conn: conn} do
    author = author_fixture()
    opinion_fixture(%{author_id: author.id, twin: false})
    location = "https://example.org/author?a=1&b=<script>\"'"

    with_mock YouCongressWeb.SEO, [:passthrough], author_url: fn _ -> location end do
      conn = get(conn, "/sitemap.xml")
      body = response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      refute body =~ "<script>"
      assert body =~ "&amp;"
      assert body =~ "&lt;script&gt;"
      assert {_document, []} = :xmerl_scan.string(String.to_charlist(body))
      locations = body |> Floki.parse_document!() |> Floki.find("loc") |> Enum.map(&Floki.text/1)
      assert location in locations
    end
  end
end
