defmodule YouCongressWeb.AuthorLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.StatementsFixtures

  @create_attrs %{
    bio: "some bio",
    country: "some country",
    twin_origin: true,
    name: "some name",
    twitter_username: "some twitter_username",
    wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
  }
  @update_attrs %{
    bio: "some updated bio",
    country: "some updated country",
    twin_origin: true,
    name: "some updated name",
    twitter_username: "whatever",
    wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
  }
  @invalid_attrs %{
    bio: nil,
    country: nil,
    twin_origin: true,
    name: nil,
    twitter_username: nil,
    wikipedia_url: nil
  }

  defp create_author(_) do
    author = author_fixture(%{twitter_username: "whatever"})
    %{author: author}
  end

  describe "Index" do
    setup [:create_author]

    test "lists all authors as admin", %{conn: conn, author: author} do
      conn = log_in_as_admin(conn)

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
      {:ok, _show_live, html} = live(conn, ~p"/x/#{author.twitter_username}")

      assert html =~ author.name
      assert html =~ author.bio
    end

    test "updates author within modal", %{conn: conn, author: author} do
      conn = log_in_as_admin(conn)
      {:ok, show_live, _html} = live(conn, ~p"/x/#{author.twitter_username}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Author"

      assert_patch(show_live, ~p"/authors/#{author}/show/edit")

      assert show_live
             |> form("#author-form", author: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#author-form", author: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/x/#{author.twitter_username}")

      html = render(show_live)
      assert html =~ "Author updated successfully"
      assert html =~ "some updated bio"
    end

    test "like icon click changes from heart.svg to filled-heart.svg", %{conn: conn} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)
      author = author_fixture(%{twitter_username: "asimov"})
      voting = statement_fixture()
      vote_fixture(%{statement_id: voting.id, author_id: author.id}, true)

      {:ok, view, _html} = live(conn, "/x/asimov")

      # We have a heart icon
      assert has_element?(view, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(view, "img[src='/images/filled-heart.svg']")

      # Like the author
      view
      |> element("img[src='/images/heart.svg']")
      |> render_click()

      # We have a filled heart icon
      assert has_element?(view, "img[src='/images/filled-heart.svg']")

      # We don't have a heart icon
      refute has_element?(view, "img[src='/images/heart.svg']")

      # Unlike the author
      view
      |> element("img[src='/images/filled-heart.svg']")
      |> render_click()

      # We have a heart icon
      assert has_element?(view, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(view, "img[src='/images/filled-heart.svg']")
    end

    test "casts a vote from voting buttons", %{conn: conn} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)
      author = author_fixture(%{twitter_username: "asimov"})
      voting = statement_fixture()
      vote_fixture(%{statement_id: voting.id, author_id: author.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/x/asimov")

      # Vote For
      show_live
      |> element("button##{voting.id}-vote-for")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted For"

      # Vote Against
      show_live
      |> element("button##{voting.id}-vote-against")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Against"

      # Vote Abstain
      show_live
      |> element("button##{voting.id}-vote-abstain")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Abstain"
    end
  end
end
