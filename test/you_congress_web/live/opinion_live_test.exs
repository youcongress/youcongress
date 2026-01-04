defmodule YouCongressWeb.OpinionLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Opinions
  alias YouCongress.Votes

  describe "Index" do
    test "comment under a comment", %{conn: conn} do
      conn = log_in_as_user(conn)
      author1 = author_fixture(%{name: "Someone1"})
      statement = statement_fixture(%{author_id: author1.id})

      opinion =
        opinion_fixture(%{
          author_id: author1.id,
          content: "Opinion1",
          statement_id: statement.id,
          twin: false
        })

      {:ok, index_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      index_live
      |> form("form", opinion: %{content: "Opinion2"})
      |> render_submit()

      assert Opinions.list_opinions() |> Enum.map(& &1.content) |> Enum.sort() == [
               "Opinion1",
               "Opinion2"
             ]
    end
  end

  describe "Show" do
    test "edit opinion from opinion show page", %{conn: conn} do
      # Create a user and author
      user = user_fixture()
      author = author_fixture(%{user_id: user.id, name: "Test Author"})
      conn = log_in_user(conn, user)

      # Create an opinion by this author
      opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Original content",
          twin: false,
          source_url: "https://example.com/source"
        })

      # Visit the opinion show page
      {:ok, show_live, html} = live(conn, ~p"/c/#{opinion.id}")

      # Check that the opinion content is displayed
      assert html =~ "Original content"
      assert html =~ "Test Author"

      # Trigger the edit event directly (since menu is JS-controlled)
      _html = render_click(show_live, "edit", %{"opinion_id" => "#{opinion.id}"})

      # Check that the edit form is now displayed
      assert has_element?(show_live, "form[phx-target]")
      assert has_element?(show_live, "textarea[name='opinion[content]']")

      # Update the opinion content using the edit component form
      show_live
      |> form("form[phx-target]", %{
        opinion: %{
          content: "Updated content",
          year: "2023",
          source_url: "https://example.com/updated-source"
        }
      })
      |> render_submit()

      # Check that we get a success message
      assert render(show_live) =~ "Opinion updated successfully"

      # Verify the opinion was actually updated in the database
      updated_opinion = Opinions.get_opinion!(opinion.id)
      assert updated_opinion.content == "Updated content"
      assert updated_opinion.year == 2023
      assert updated_opinion.source_url == "https://example.com/updated-source"

      # Check that the edit form is hidden again
      refute has_element?(show_live, "form[phx-target]")
      assert render(show_live) =~ "Updated content"
    end

    test "edit opinion author from opinion show page", %{conn: conn} do
      # Create a user and two authors
      user = user_fixture()
      original_author = author_fixture(%{user_id: user.id, name: "Original Author"})
      new_author = author_fixture(%{user_id: user.id, name: "New Author"})
      conn = log_in_user(conn, user)

      # Create a statement and opinion by the original author
      statement = statement_fixture()

      opinion =
        opinion_fixture(%{
          author_id: original_author.id,
          user_id: user.id,
          content: "Original content",
          twin: false,
          source_url: "https://example.com/source"
        })

      # Create a vote for the original author on this statement with this opinion
      vote =
        vote_fixture(%{
          author_id: original_author.id,
          statement_id: statement.id,
          opinion_id: opinion.id
        })

      # Visit the opinion show page
      {:ok, show_live, html} = live(conn, ~p"/c/#{opinion.id}")

      # Check that the original author is displayed
      assert html =~ "Original Author"

      # Trigger the edit event directly (since menu is JS-controlled)
      _html = render_click(show_live, "edit", %{"opinion_id" => "#{opinion.id}"})

      # Check that the edit form is now displayed
      assert has_element?(show_live, "form[phx-target]")
      assert has_element?(show_live, "input[name='author_search']")

      # Open the author dropdown by clicking on the search input
      show_live
      |> element("input[name='author_search']")
      |> render_click()

      # Search for the new author to filter the list
      show_live
      |> element("input[name='author_search']")
      |> render_change(%{author_search: "New Author"})

      # Click on the new author from the dropdown
      show_live
      |> element("#author_option_#{new_author.id}")
      |> render_click()

      # Update the opinion content using the edit component form
      show_live
      |> form("form[phx-target]", %{
        opinion: %{
          content: "Updated content",
          year: "2023",
          source_url: "https://example.com/updated-source"
        }
      })
      |> render_submit()

      # Check that we get a success message
      assert render(show_live) =~ "Opinion updated successfully"

      # Verify the opinion was actually updated in the database
      updated_opinion = Opinions.get_opinion!(opinion.id, preload: [:author])
      assert updated_opinion.content == "Updated content"
      assert updated_opinion.year == 2023
      assert updated_opinion.source_url == "https://example.com/updated-source"
      assert updated_opinion.author_id == new_author.id
      assert updated_opinion.author.name == "New Author"

      # Verify that the vote's author_id was also updated to the new author
      updated_vote = Votes.get_vote!(vote.id)

      assert updated_vote.author_id == new_author.id,
             "Vote's author_id should be updated to match the new opinion author"

      # Check that the edit form is hidden again
      refute has_element?(show_live, "form[phx-target]")
      assert render(show_live) =~ "Updated content"
      assert render(show_live) =~ "New Author"
    end

    test "cancel edit opinion from opinion show page", %{conn: conn} do
      # Create a user and author
      user = user_fixture()
      author = author_fixture(%{user_id: user.id, name: "Test Author"})
      conn = log_in_user(conn, user)

      # Create an opinion by this author
      opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Original content",
          twin: false
        })

      # Visit the opinion show page
      {:ok, show_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      # Trigger the edit event directly (since menu is JS-controlled)
      render_click(show_live, "edit", %{"opinion_id" => "#{opinion.id}"})

      # Check that the edit form is displayed
      assert has_element?(show_live, "form[phx-target]")

      # Click cancel button on the edit component
      show_live
      |> element("button[phx-click='cancel'][phx-target]")
      |> render_click()

      # Check that the edit form is hidden again
      refute has_element?(show_live, "form[phx-target]")
      assert render(show_live) =~ "Original content"

      # Verify the opinion was not changed in the database
      unchanged_opinion = Opinions.get_opinion!(opinion.id)
      assert unchanged_opinion.content == "Original content"
    end

    test "edit child opinion from opinion show page", %{conn: conn} do
      # Create a user and author
      user = user_fixture()
      author = author_fixture(%{user_id: user.id, name: "Test Author"})
      conn = log_in_user(conn, user)

      # Create a parent opinion
      parent_opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Parent opinion",
          twin: false
        })

      # Create a child opinion (comment)
      child_opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Child comment",
          ancestry: "#{parent_opinion.id}",
          twin: false
        })

      # Visit the parent opinion show page
      {:ok, show_live, html} = live(conn, ~p"/c/#{parent_opinion.id}")

      # Check that both opinions are displayed
      assert html =~ "Parent opinion"
      assert html =~ "Child comment"

      # Trigger the edit event for the child opinion directly
      render_click(show_live, "edit", %{"opinion_id" => "#{child_opinion.id}"})

      # Update the child opinion content using the edit component form
      show_live
      |> form("form[phx-target]", %{
        opinion: %{content: "Updated child comment"}
      })
      |> render_submit()

      # Check that we get a success message
      assert render(show_live) =~ "Opinion updated successfully"

      # Verify the child opinion was updated
      updated_child = Opinions.get_opinion!(child_opinion.id)
      assert updated_child.content == "Updated child comment"

      # Verify the parent opinion was not changed
      unchanged_parent = Opinions.get_opinion!(parent_opinion.id)
      assert unchanged_parent.content == "Parent opinion"
    end

    test "non-owner cannot edit opinion", %{conn: conn} do
      # Create two users
      owner_user = user_fixture()
      owner_author = author_fixture(%{user_id: owner_user.id, name: "Owner"})

      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      # Create an opinion by the owner
      opinion =
        opinion_fixture(%{
          author_id: owner_author.id,
          user_id: owner_user.id,
          content: "Owner's opinion",
          twin: false
        })

      # Visit the opinion show page as the other user
      {:ok, show_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      # Check that the opinion content is displayed (HTML-encoded apostrophe)
      html_content = render(show_live)
      assert html_content =~ "Owner&#39;s opinion"

      # Check that there's no edit button for non-owner
      # (since menu is JS-controlled, we just verify no edit form appears)
      refute has_element?(show_live, "form[phx-target]")
    end
  end
end
