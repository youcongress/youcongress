defmodule YouCongressWeb.ReconsiderLiveTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.Reconsiderations

  setup do
    creator = creator_fixture()
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
    {:ok, view, html} = live(conn, reconsideration_path(context))

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
    {:ok, view, _html} = live(conn, reconsideration_path(context))

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

    assert_redirect(
      view,
      "/@#{context.creator.author.username}/r/a-second-city-streets-article"
    )
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

  test "the legacy URL redirects permanently to the creator URL", %{conn: conn} = context do
    conn = get(conn, ~p"/reconsider/#{context.reconsideration.slug}")
    assert redirected_to(conn, 301) == reconsideration_path(context)
  end

  test "a normal user cannot open the creation form", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/reconsider/new")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "creator or admin"
  end

  test "an admin can open the creation form", %{conn: conn} do
    admin = admin_fixture() |> with_username()
    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/reconsider/new")
    assert html =~ "Create a Reconsider page"
  end

  test "a creator chooses a username before creating a page", %{conn: conn} do
    {:ok, creator_without_username} =
      user_fixture()
      |> Accounts.update_role("creator")

    conn = log_in_user(conn, creator_without_username)

    assert {:error, {:redirect, %{to: "/settings"}}} = live(conn, ~p"/reconsider/new")
  end

  defp creator_fixture do
    {:ok, creator} =
      user_fixture()
      |> Accounts.update_role("creator")

    with_username(creator)
  end

  defp with_username(user) do
    username = "alice_#{System.unique_integer([:positive])}" |> String.slice(0, 15)

    {:ok, author} =
      user.author_id
      |> Authors.get_author!()
      |> Authors.update_author(%{username: username})

    %{user | author: author}
  end

  defp reconsideration_path(context) do
    "/@#{context.creator.author.username}/r/#{context.reconsideration.slug}"
  end
end
