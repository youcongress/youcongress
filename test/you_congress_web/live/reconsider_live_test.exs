defmodule YouCongressWeb.ReconsiderLiveTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
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
        "delegate_ids" => []
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
        "delegate_ids" => []
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
    refute html =~ "For creators"
    assert has_element?(view, "#reconsideration_content_url[placeholder='https://...']")

    select_statement(view, context.statement, "private cars")

    params = %{
      "reconsideration" => %{
        "title" => "A second city-streets article",
        "description" => "Consider the evidence.",
        "content_url" => "https://example.com/second-article",
        "content_type" => "article"
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
    select_statement(view, context.statement, "private cars")

    html =
      render_submit(view, "save", %{
        "reconsideration" => %{
          "title" => "Invalid URL example",
          "description" => "",
          "content_url" => "not-a-url",
          "content_type" => "article"
        }
      })

    assert html =~ "must be a valid HTTP or HTTPS URL"
    assert html =~ context.statement.title
    assert has_element?(view, "#selected-statement-#{context.statement.id}")
  end

  test "statements and delegates can be searched, selected, and removed",
       %{
         conn: conn
       } = context do
    second_statement = statement_fixture(%{title: "Nuclear power should be expanded rapidly"})

    delegate =
      author_fixture(%{
        name: "Ada Energy",
        username: "ada_energy",
        bio: "Writes about advanced reactors and clean grids"
      })

    conn = log_in_user(conn, context.creator)
    {:ok, view, _html} = live(conn, ~p"/reconsider/new")

    select_statement(view, context.statement, "private cars")
    select_statement(view, second_statement, "nuclear power")

    assert has_element?(view, "#selected-statement-#{context.statement.id}")
    assert has_element?(view, "#selected-statement-#{second_statement.id}")

    view
    |> element("#selected-statement-#{context.statement.id} button")
    |> render_click()

    refute has_element?(view, "#selected-statement-#{context.statement.id}")

    view
    |> element("#delegate-search")
    |> render_change(%{"delegate_search" => "advanced reactors"})

    assert has_element?(view, "#delegate-result-#{delegate.id}")

    view
    |> element("#delegate-result-#{delegate.id}")
    |> render_click()

    assert has_element?(view, "#selected-delegate-#{delegate.id}")
    assert render(view) =~ "@ada_energy"

    view
    |> element("#selected-delegate-#{delegate.id} button")
    |> render_click()

    refute has_element?(view, "#selected-delegate-#{delegate.id}")
  end

  test "the statement picker stops at three selections", %{conn: conn} = context do
    second_statement = statement_fixture(%{title: "Nuclear power should be expanded rapidly"})
    third_statement = statement_fixture(%{title: "Cities should build more tram lines"})

    conn = log_in_user(conn, context.creator)
    {:ok, view, html} = live(conn, ~p"/reconsider/new")

    assert html =~ "YouCongress statements (1–3)"

    select_statement(view, context.statement, "private cars")
    select_statement(view, second_statement, "nuclear power")
    select_statement(view, third_statement, "tram lines")

    refute has_element?(view, "#statement-search")
    assert render(view) =~ "maximum of three statements"
  end

  test "statement autocomplete supports keyboard selection", %{conn: conn} = context do
    conn = log_in_user(conn, context.creator)
    {:ok, view, _html} = live(conn, ~p"/reconsider/new")

    view
    |> element("#statement-search")
    |> render_change(%{"statement_search" => "private cars"})

    assert has_element?(
             view,
             "#statement-search[aria-activedescendant='statement-result-#{context.statement.id}']"
           )

    view
    |> element("#statement-search")
    |> render_keydown(%{"key" => "Enter"})

    assert_push_event(view, "clear-autocomplete", %{id: "statement-search"})
    assert has_element?(view, "#selected-statement-#{context.statement.id}")
    refute has_element?(view, "#statement-results")
  end

  test "delegate autocomplete ranks direct name matches first", %{conn: conn} = context do
    _ada =
      author_fixture(%{
        name: "Ada Colau",
        username: "ada_colau",
        bio: "Former mayor of Barcelona"
      })

    elon =
      author_fixture(%{
        name: "Elon Musk",
        username: "elon_musk",
        bio: "Technology entrepreneur"
      })

    conn = log_in_user(conn, context.creator)
    {:ok, view, html} = live(conn, ~p"/reconsider/new")

    assert html =~ "People from the article/video viewers may delegate to (optional)"

    view
    |> element("#delegate-search")
    |> render_change(%{"delegate_search" => "elon"})

    assert has_element?(view, "#delegate-results button:first-child", "Elon Musk")
    assert has_element?(view, "#delegate-result-#{elon.id}")

    assert has_element?(
             view,
             "#delegate-search[aria-activedescendant='delegate-result-#{elon.id}']"
           )

    view
    |> element("#delegate-search")
    |> render_keydown(%{"key" => "ArrowDown"})

    refute has_element?(
             view,
             "#delegate-search[aria-activedescendant='delegate-result-#{elon.id}']"
           )

    view
    |> element("#delegate-search")
    |> render_keydown(%{"key" => "ArrowUp"})

    assert has_element?(
             view,
             "#delegate-search[aria-activedescendant='delegate-result-#{elon.id}']"
           )

    view
    |> element("#delegate-search")
    |> render_keydown(%{"key" => "Enter"})

    assert_push_event(view, "clear-autocomplete", %{id: "delegate-search"})
    assert has_element?(view, "#selected-delegate-#{elon.id}")
    refute has_element?(view, "#delegate-results")
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

  defp select_statement(view, statement, query) do
    view
    |> element("#statement-search")
    |> render_change(%{"statement_search" => query})

    assert has_element?(view, "#statement-result-#{statement.id}")

    view
    |> element("#statement-result-#{statement.id}")
    |> render_click()
  end
end
