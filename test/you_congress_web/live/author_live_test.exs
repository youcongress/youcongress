defmodule YouCongressWeb.AuthorLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.CountriesFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.OpinionsFixtures

  alias YouCongress.Opinions

  @create_attrs %{
    bio: "some bio",
    twin_origin: true,
    name: "some name",
    twitter_username: "some twitter_username",
    wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
  }
  @update_attrs %{
    bio: "some updated bio",
    twin_origin: true,
    name: "some updated name",
    twitter_username: "whatever",
    wikipedia_url: "https://en.wikipedia.org/wiki/whatever"
  }
  @invalid_attrs %{
    bio: nil,
    country_id: nil,
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
      country = country_fixture(name: "Some Country")

      {:ok, index_live, _html} = live(conn, ~p"/authors")

      assert index_live |> element("a", "New Author") |> render_click() =~
               "New Author"

      assert_patch(index_live, ~p"/authors/new")

      assert index_live
             |> form("#author-form", author: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#author-form", author: Map.put(@create_attrs, :country_id, country.id))
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
      {:ok, show_live, html} = live(conn, ~p"/x/#{author.twitter_username}")

      assert html =~ author.name
      assert html =~ author.bio

      assert has_element?(
               show_live,
               "a[aria-label='Open X profile for #{author.twitter_username}']"
             )

      assert has_element?(show_live, "a[href='https://x.com/#{author.twitter_username}']")
      assert has_element?(show_live, "img[src='/images/x.svg'][alt='X']")
      assert has_element?(show_live, "a[aria-label='Open Wikipedia page']")
      assert has_element?(show_live, "a[href='#{author.wikipedia_url}']")
      assert has_element?(show_live, "img[src='/images/wikipedia.svg'][alt='Wikipedia']")
      refute html =~ "X: @#{author.twitter_username}"
      refute has_element?(show_live, "a", "Wikipedia")
    end

    test "lets visitors switch between an author's sourced quotes for a statement", %{conn: conn} do
      twitter_username = "multi_quote_author_#{System.unique_integer([:positive])}"
      author = author_fixture(%{twitter_username: twitter_username})
      statement = statement_fixture(title: "Author multi quote statement")

      older_opinion =
        opinion_fixture(%{
          author_id: author.id,
          content: "Older author page quote",
          source_url: "https://example.com/author-older",
          year: 2023
        })

      newer_opinion =
        opinion_fixture(%{
          author_id: author.id,
          content: "Newer author page quote",
          source_url: "https://example.com/author-newer",
          year: 2024
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_opinion, statement.id)
      {:ok, _} = Opinions.add_opinion_to_statement(newer_opinion, statement.id)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: newer_opinion.id,
          answer: :for
        })

      {:ok, view, html} = live(conn, ~p"/x/#{twitter_username}")

      assert html =~ statement.title
      assert html =~ "Newer author page quote"
      refute html =~ "Older author page quote"
      assert has_element?(view, "[data-testid='quote-position-#{vote.id}']", "1 of 2")

      view
      |> element("[data-testid='vote-card-#{vote.id}'] button[aria-label='Next quote']")
      |> render_click()

      html = render(view)
      assert html =~ "Older author page quote"
      assert has_element?(view, "[data-testid='quote-position-#{vote.id}']", "2 of 2")
    end

    test "updates author within modal", %{conn: conn, author: author} do
      conn = log_in_as_admin(conn)
      country = country_fixture(name: "Updated Country")
      {:ok, show_live, _html} = live(conn, ~p"/x/#{author.twitter_username}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Author"

      assert_patch(show_live, ~p"/authors/#{author}/show/edit")

      assert show_live
             |> form("#author-form", author: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#author-form", author: Map.put(@update_attrs, :country_id, country.id))
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
      statement = statement_fixture()
      vote_fixture(%{statement_id: statement.id, author_id: author.id}, true)

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
      statement = statement_fixture()
      vote_fixture(%{statement_id: statement.id, author_id: author.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/x/asimov")

      # Vote For
      show_live
      |> element("button##{statement.id}-vote-for")
      |> render_click()

      assert show_live |> element("button##{statement.id}-vote-for") |> render() =~ "✓"
      assert show_live |> element("button##{statement.id}-vote-for") |> render() =~ "For"

      # Vote Against
      show_live
      |> element("button##{statement.id}-vote-against")
      |> render_click()

      assert show_live |> element("button##{statement.id}-vote-against") |> render() =~ "✓"
      assert show_live |> element("button##{statement.id}-vote-against") |> render() =~ "Against"

      # Vote Abstain
      show_live
      |> element("button##{statement.id}-vote-abstain")
      |> render_click()

      assert show_live |> element("button##{statement.id}-vote-abstain") |> render() =~ "✓"
      assert show_live |> element("button##{statement.id}-vote-abstain") |> render() =~ "Abstain"
    end

    test "loads country vote results on author page only after clicking by country", %{conn: conn} do
      unique = System.unique_integer([:positive])
      author_country = country_fixture(%{name: "Author Vote Country #{unique}"})
      voter_country = country_fixture(%{name: "Author Page Voter Country #{unique}"})

      current_user =
        user_fixture(%{}, %{
          name: "Author Page Voter #{unique}",
          twitter_username: "author_page_voter_#{unique}",
          bio: "Bio",
          wikipedia_url: "https://en.wikipedia.org/wiki/Author_Page_Voter_#{unique}",
          twin_origin: false,
          country_id: voter_country.id
        })

      conn = log_in_user(conn, current_user)
      author = author_fixture(%{twitter_username: "asimov", country_id: author_country.id})
      statement = statement_fixture()
      vote_fixture(%{statement_id: statement.id, author_id: author.id, answer: :against}, true)

      {:ok, show_live, html} = live(conn, ~p"/x/asimov")

      assert html =~ statement.title
      refute html =~ voter_country.name

      html =
        show_live
        |> element("button##{statement.id}-vote-for")
        |> render_click()

      assert html =~ "By country"
      refute html =~ voter_country.name

      html =
        show_live
        |> element("button##{statement.id}-results-by-country", "By country")
        |> render_click()

      assert html =~ voter_country.name
    end
  end
end
