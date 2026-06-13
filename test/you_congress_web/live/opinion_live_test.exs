defmodule YouCongressWeb.OpinionLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.Votes
  alias YouCongress.VoteVerifications
  alias YouCongress.Verifications

  defp pick_and_save(view, scope, subject, status, comment) do
    view
    |> element(~s|#{scope} button[phx-value-subject="#{subject}"][phx-value-status="#{status}"]|)
    |> render_click()

    view
    |> element(~s|#{scope} input[data-testid="verification-comment-input-#{subject}"]|)
    |> render_keyup(%{"value" => comment})

    view
    |> element(~s|#{scope} button[data-testid="verification-save-#{subject}"]|)
    |> render_click()
  end

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

    test "shows verification history on opinion show page", %{conn: conn} do
      user = user_fixture()
      opinion = opinion_fixture(%{content: "Verified opinion"})

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "This checks out"
        })

      {:ok, _view, html} = live(conn, ~p"/c/#{opinion.id}")

      assert html =~ "Verification History"
      assert html =~ "Verified"
      assert html =~ "This checks out"
    end

    test "displays AI verification model in history", %{conn: conn} do
      user = user_fixture()
      opinion = opinion_fixture(%{content: "AI verified opinion"})

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :ai_verified,
          comment: "Checked by AI",
          model: "opus-4.6"
        })

      {:ok, _view, html} = live(conn, ~p"/c/#{opinion.id}")

      assert html =~ "opus-4.6"
      assert html =~ "AI model: opus-4.6"
    end

    test "verification history updates after badge verification", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      opinion =
        opinion_fixture(%{
          content: "Quote to verify",
          source_url: "https://example.com/source",
          twin: true
        })

      # Add a statement so the badge shows (badge requires source_url)
      statement = statement_fixture()

      vote_fixture(%{
        statement_id: statement.id,
        author_id: opinion.author_id,
        opinion_id: opinion.id
      })

      {:ok, view, _html} = live(conn, ~p"/c/#{opinion.id}")

      # Initially no verification history
      refute render(view) =~ "Verification History"

      # Create a verification directly
      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :disputed,
          comment: "Source seems wrong"
        })

      # Send the message that the badge would send
      send(view.pid, {:verification_saved, :opinion, opinion.id})

      html = render(view)
      assert html =~ "Verification History"
      assert html =~ "Disputed"
      assert html =~ "Source seems wrong"
    end

    test "verification history shows multiple entries", %{conn: conn} do
      user1 = user_fixture()
      user2 = user_fixture()
      opinion = opinion_fixture(%{content: "Multi-verified opinion"})

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user1.id,
          status: :verified,
          comment: "Looks good"
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user2.id,
          status: :disputed,
          comment: "I disagree"
        })

      {:ok, _view, html} = live(conn, ~p"/c/#{opinion.id}")

      assert html =~ "Looks good"
      assert html =~ "I disagree"
      assert html =~ "Verified"
      assert html =~ "Disputed"
    end

    test "shows relation and vote verification histories for each statement", %{conn: conn} do
      user = user_fixture()
      author = author_fixture(%{name: "Quote Author"})
      statement = statement_fixture(%{title: "We should deliberate publicly"})

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "A quote with full verification history",
          source_url: "https://example.com/source",
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: opinion.id,
          answer: :for
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Quote authentic"
        })

      opinion_statement = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)

      {:ok, _} =
        OpinionStatementVerifications.create_verification(%{
          opinion_statement_id: opinion_statement.id,
          user_id: user.id,
          status: :verified,
          comment: "Relation is exact"
        })

      {:ok, _} =
        VoteVerifications.create_verification(%{
          vote_id: vote.id,
          user_id: user.id,
          status: :disputed,
          comment: "Vote answer needs review"
        })

      {:ok, _view, html} = live(conn, ~p"/c/#{opinion.id}")

      assert html =~ "Verification History"
      assert html =~ "Quote authentic"
      assert html =~ "Statement relation"
      assert html =~ "Relation is exact"
      assert html =~ "Vote answer"
      assert html =~ "Vote answer needs review"
    end

    test "shows empty relation row when only vote answer history is visible", %{conn: conn} do
      user = user_fixture()
      author = author_fixture(%{name: "Quote Author"})
      statement = statement_fixture(%{title: "We should deliberate publicly"})

      shown_quote =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Shown quote",
          source_url: "https://example.com/shown",
          twin: false
        })

      voted_quote =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Voted quote",
          source_url: "https://example.com/voted",
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(shown_quote, statement.id)
      {:ok, _} = Opinions.add_opinion_to_statement(voted_quote, statement.id)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: voted_quote.id,
          answer: :for
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: voted_quote.id,
          user_id: user.id,
          status: :verified,
          comment: "Voted quote authentic"
        })

      voted_relation = OpinionsStatements.get_opinion_statement(voted_quote.id, statement.id)

      {:ok, _} =
        OpinionStatementVerifications.create_verification(%{
          opinion_statement_id: voted_relation.id,
          user_id: user.id,
          status: :verified,
          comment: "Voted quote relation is exact"
        })

      {:ok, _} =
        VoteVerifications.create_verification(%{
          vote_id: vote.id,
          user_id: user.id,
          status: :verified,
          comment: "Vote answer is correct"
        })

      {:ok, _view, html} = live(conn, ~p"/c/#{shown_quote.id}")

      assert html =~ "Statement relation"
      assert html =~ "No statement relation verification comments yet."
      assert html =~ "Vote answer"
      assert html =~ "Vote answer is correct"
    end

    test "shows step-by-step verification badge and vote next to each statement", %{conn: conn} do
      user = user_fixture(%{role: "moderator"})
      author = author_fixture(%{name: "Quote Author"})
      conn = log_in_user(conn, user)

      statement = statement_fixture(%{title: "We should deliberate publicly"})

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "A citable quote",
          source_url: "https://example.com/source",
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: author.id,
        opinion_id: opinion.id,
        answer: :for
      })

      {:ok, view, html} = live(conn, ~p"/c/#{opinion.id}")

      # The statement is listed with the author's vote answer
      assert html =~ "We should deliberate publicly"
      assert html =~ "votes For"

      # The statement verification area is rendered next to the statement.
      card = ~s|[data-testid="statement-verify-#{statement.id}"]|
      assert has_element?(view, card)

      # Clicking a verification badge reveals the step-by-step editor and lets
      # the user verify each part (quote -> relation -> vote answer) with a
      # comment, gated progressively.
      view
      |> element(
        ~s|#{card} button[data-testid="statement-relation-verification-badge-#{statement.id}"]|
      )
      |> render_click()

      btn = fn subject, status ->
        ~s|#{card} button[phx-value-subject="#{subject}"][phx-value-status="#{status}"]|
      end

      assert has_element?(view, btn.("quote", "verified"))
      refute has_element?(view, btn.("relevance", "verified"))

      pick_and_save(view, card, "quote", "verified", "Quote is authentic")
      assert has_element?(view, btn.("relevance", "verified"))

      pick_and_save(view, card, "relevance", "verified", "Quote matches statement")
      assert has_element?(view, btn.("vote", "verified"))
    end

    test "blank verification comments are stored as nil", %{conn: conn} do
      user = user_fixture(%{role: "moderator"})
      author = author_fixture(%{name: "Quote Author"})
      conn = log_in_user(conn, user)

      statement = statement_fixture(%{title: "We should deliberate publicly"})

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "A citable quote",
          source_url: "https://example.com/source",
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: opinion.id,
          answer: :for
        })

      {:ok, view, _html} = live(conn, ~p"/c/#{opinion.id}")
      card = ~s|[data-testid="statement-verify-#{statement.id}"]|

      view
      |> element(
        ~s|#{card} button[data-testid="statement-relation-verification-badge-#{statement.id}"]|
      )
      |> render_click()

      pick_and_save(view, card, "quote", "verified", "")
      pick_and_save(view, card, "relevance", "verified", "")
      pick_and_save(view, card, "vote", "verified", "")

      [quote_verification] = Verifications.list_verifications(opinion_id: opinion.id)
      opinion_statement = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)

      [relation_verification] =
        OpinionStatementVerifications.list_verifications(
          opinion_statement_id: opinion_statement.id
        )

      [vote_verification] = VoteVerifications.list_verifications(vote_id: vote.id)

      assert quote_verification.comment == nil
      assert relation_verification.comment == nil
      assert vote_verification.comment == nil
    end

    test "can verify the vote even when it is backed by a different quote", %{conn: conn} do
      user = user_fixture(%{role: "moderator"})
      author = author_fixture(%{name: "Quote Author"})
      conn = log_in_user(conn, user)

      statement = statement_fixture(%{title: "We should deliberate publicly"})

      # The author's vote on the statement is backed by a primary quote...
      primary_quote =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Primary quote",
          source_url: "https://example.com/primary",
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(primary_quote, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: author.id,
        opinion_id: primary_quote.id,
        answer: :for
      })

      # ...but we're viewing a secondary quote also linked to the statement.
      secondary_quote =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Secondary quote",
          source_url: "https://example.com/secondary",
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(secondary_quote, statement.id)

      {:ok, view, _html} = live(conn, ~p"/c/#{secondary_quote.id}")

      card = ~s|[data-testid="statement-verify-#{statement.id}"]|

      btn = fn subject, status ->
        ~s|#{card} button[phx-value-subject="#{subject}"][phx-value-status="#{status}"]|
      end

      view
      |> element(~s|#{card} button[data-testid="vote-answer-verification-badge-#{statement.id}"]|)
      |> render_click()

      pick_and_save(view, card, "quote", "verified", "Quote is authentic")
      pick_and_save(view, card, "relevance", "verified", "Quote matches statement")

      # The vote row is actionable (no longer "n/a for this quote").
      assert has_element?(view, btn.("vote", "verified"))
      refute render(view) =~ "n/a for this quote"
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

      render_click(show_live, "edit", %{"opinion_id" => "#{opinion.id}"})

      refute has_element?(show_live, "form[phx-target]")
      assert render(show_live) =~ "You are not allowed to edit this opinion."

      unchanged_opinion = Opinions.get_opinion!(opinion.id)
      assert unchanged_opinion.content == "Owner's opinion"
    end
  end
end
