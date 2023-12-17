defmodule YouCongressWeb.AuthorLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures

  @create_attrs %{
    bio: "some bio",
    country: "some country",
    is_twin: true,
    name: "some name",
    twitter_url: "some twitter_url",
    wikipedia_url: "some wikipedia_url"
  }
  @update_attrs %{
    bio: "some updated bio",
    country: "some updated country",
    is_twin: true,
    name: "some updated name",
    twitter_url: "some updated twitter_url",
    wikipedia_url: "some updated wikipedia_url"
  }
  @invalid_attrs %{
    bio: nil,
    country: nil,
    is_twin: true,
    name: nil,
    twitter_url: nil,
    wikipedia_url: nil
  }

  defp create_author(_) do
    author = author_fixture()
    %{author: author}
  end

  describe "Index" do
    setup [:create_author]

    test "lists all authors", %{conn: conn, author: author} do
      conn = log_in_as_user(conn)

      {:ok, _index_live, html} = live(conn, ~p"/authors")

      assert html =~ "Listing Authors"
      assert html =~ author.bio
    end

    test "saves new author", %{conn: conn} do
      conn = log_in_as_admin(conn)

      {:ok, index_live, _html} = live(conn, ~p"/authors")

      assert index_live |> element("a", "New Author") |> render_click() =~
               "New Author"

      assert_patch(index_live, ~p"/authors/new")

      assert index_live
             |> form("#author-form", author: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#author-form", author: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/authors")

      html = render(index_live)
      assert html =~ "Author created successfully"
      assert html =~ "some bio"
    end
  end

  describe "Show" do
    setup [:create_author]

    test "displays author", %{conn: conn, author: author} do
      conn = log_in_as_user(conn)
      {:ok, _show_live, html} = live(conn, ~p"/authors/#{author}")

      assert html =~ "Show Author"
      assert html =~ author.bio
    end

    test "updates author within modal", %{conn: conn, author: author} do
      conn = log_in_as_admin(conn)
      {:ok, show_live, _html} = live(conn, ~p"/authors/#{author}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Author"

      assert_patch(show_live, ~p"/authors/#{author}/show/edit")

      assert show_live
             |> form("#author-form", author: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#author-form", author: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/authors/#{author}")

      html = render(show_live)
      assert html =~ "Author updated successfully"
      assert html =~ "some updated bio"
    end
  end
end
