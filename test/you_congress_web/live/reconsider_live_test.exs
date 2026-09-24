defmodule YouCongressWeb.ReconsiderLiveTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Reconsiderations

  setup do
    creator = user_fixture()
    statement = statement_fixture(%{title: "Cities should remove private cars from downtown"})

    {:ok, reconsideration} =
      Reconsiderations.create_reconsideration(
        creator,
        %{
          "title" => "Rethinking city streets",
          "content_url" => "https://example.com/article",
          "content_type" => "article"
        },
        [statement.id],
        []
      )

    %{creator: creator, statement: statement, reconsideration: reconsideration}
  end

  test "a guest selects everything before being asked to authenticate", %{conn: conn} = context do
    {:ok, view, html} = live(conn, ~p"/reconsider/#{context.reconsideration.slug}")

    assert html =~ "Rethinking city streets"
    assert html =~ "Before this article"
    refute html =~ "Sign in to record your response"

    params = %{
      "response" => %{
        "answers" => %{
          to_string(context.statement.id) => %{"before" => "against", "after" => "for"}
        },
        "delegate_ids" => [to_string(context.creator.author_id)]
      }
    }

    html = render_submit(view, "submit", params)
    assert html =~ "Sign in to record your response"
    assert html =~ "Log in with Google"
    refute html =~ "Community result"
  end

  test "an authenticated participant saves once and sees change statistics",
       %{conn: conn} = context do
    participant = user_fixture()
    conn = log_in_user(conn, participant)
    {:ok, view, _html} = live(conn, ~p"/reconsider/#{context.reconsideration.slug}")

    params = %{
      "response" => %{
        "answers" => %{
          to_string(context.statement.id) => %{"before" => "against", "after" => "for"}
        },
        "delegate_ids" => [to_string(context.creator.author_id)]
      }
    }

    html = render_submit(view, "submit", params)
    assert html =~ "Community result"
    assert html =~ "100%"
    assert html =~ "Changed"
    assert html =~ "self-reported result"
  end

  test "an authenticated creator can build a shareable page", %{conn: conn} = context do
    conn = log_in_user(conn, context.creator)
    {:ok, view, html} = live(conn, ~p"/reconsider/new")
    assert html =~ "Create a Reconsider page"

    params = %{
      "reconsideration" => %{
        "title" => "A second city-streets article",
        "description" => "Consider the evidence.",
        "content_url" => "https://example.com/second-article",
        "content_type" => "article",
        "statement_refs" => "/p/#{context.statement.slug}",
        "delegate_refs" => ""
      }
    }

    render_submit(view, "save", params)
    assert_redirect(view, "/reconsider/a-second-city-streets-article")
  end

  test "creator form keeps its references when validation fails", %{conn: conn} = context do
    conn = log_in_user(conn, context.creator)
    {:ok, view, _html} = live(conn, ~p"/reconsider/new")

    html =
      render_submit(view, "save", %{
        "reconsideration" => %{
          "title" => "Invalid URL example",
          "description" => "",
          "content_url" => "not-a-url",
          "content_type" => "article",
          "statement_refs" => "/p/#{context.statement.slug}",
          "delegate_refs" => ""
        }
      })

    assert html =~ "must be a valid HTTP or HTTPS URL"
    assert html =~ context.statement.slug
  end
end
