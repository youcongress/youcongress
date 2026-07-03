defmodule YouCongressWeb.StatementLive.VoteComponent.QuoteMenuTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest

  alias YouCongressWeb.StatementLive.VoteComponent.QuoteMenu

  test "report comment links to a prefilled contact form" do
    html =
      render_component(&QuoteMenu.render/1,
        id: "quote-123",
        author: %{twitter_username: nil},
        opinion: %{
          id: 123,
          twin: false,
          source_url: nil,
          source_text: nil,
          ancestry: nil,
          author_id: 1
        },
        current_user: %{author_id: 2},
        statement: %{slug: "test-statement"},
        page: :statement_show
      )

    href =
      html
      |> Floki.parse_fragment!()
      |> Floki.find("a")
      |> Enum.map(&Floki.attribute(&1, "href"))
      |> List.flatten()
      |> Enum.find(&String.starts_with?(&1, "/contact?"))

    query = href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert query["subject"] == "Report comment"

    comment_uri = URI.parse(query["body"])
    assert comment_uri.scheme in ["http", "https"]
    assert comment_uri.path == "/c/123"
  end

  test "does not render a report link without an opinion" do
    html =
      render_component(&QuoteMenu.render/1,
        id: "vote-123",
        author: %{twitter_username: nil},
        opinion: nil,
        current_user: nil,
        statement: %{slug: "test-statement"},
        page: :author_show
      )

    refute html =~ "Report comment"
  end
end
