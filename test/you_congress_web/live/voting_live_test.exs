defmodule YouCongressWeb.VotingLiveTest do
  use YouCongressWeb.ConnCase

  import Mock

  import Phoenix.LiveViewTest
  import YouCongress.VotingsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.AuthorsFixtures


  alias YouCongress.Votes.Answers
  alias YouCongress.Votings
  alias YouCongress.HallsVotings

  @create_attrs %{title: "nuclear energy"}
  @suggested_titles [
    "Should we increase investment in nuclear energy research?",
    "Shall we consider nuclear energy as a viable alternative to fossil fuels?",
    "Could nuclear energy be a key solution for reducing global carbon emissions?"
  ]
  @update_attrs %{title: "some updated title"}
  @invalid_attrs %{title: nil}

  defp create_voting(_) do
    voting = voting_fixture()
    {:ok, _} = HallsVotings.sync!(voting.id, ["ai"])

    %{voting: voting}
  end

  describe "Index" do
    setup [:create_voting]

    test "vote and create opinion", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)
      {:ok, index_live, html} = live(conn, ~p"/home")

      assert html =~ "YouCongress: Finding solutions to our most important problems"

      assert html =~
               "Finding agreements and understanding disagreements to improve our democracies. Open Source."

      assert html =~ voting.title

      #  Vote strongly agree
      index_live
      |> element("button##{voting.id}-vote-strongly-agree")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted Strongly agree"

      # Vote agree
      index_live
      |> element("button##{voting.id}-vote-agree")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted Agree"

      # Vote Abstain
      index_live
      |> element("button##{voting.id}-vote-abstain")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted Abstain"

      # Vote N/A
      index_live
      |> element("button##{voting.id}-vote-na")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted N/A"

      # Vote disagree
      index_live
      |> element("button##{voting.id}-vote-disagree")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted Disagree"

      # Vote strongly disagree
      index_live
      |> element("button##{voting.id}-vote-strongly-disagree")
      |> render_click()

      html = render(index_live)
      assert html =~ "You voted Strongly disagree"

      # Create a comment
      index_live
      |> form("#v#{voting.id}-opinion-form", %{"opinion[content]" => "some comment"})
      |> render_submit()

      html = render(index_live)
      assert html =~ "Opinion created successfully"
      assert html =~ "some comment"

      index_live
      |> form("#v#{voting.id}-opinion-form", %{"opinion[content]" => "some updated comment"})
      |> render_submit()

      html = render(index_live)
      assert html =~ "Opinion updated successfully"
      assert html =~ "some updated comment"
    end

    test "saves new voting and redirect to show", %{conn: conn} do
      with_mocks([
        {YouCongress.Votings.TitleRewording, [],
         [generate_rewordings: fn _, _ -> {:ok, @suggested_titles, 0} end]}
      ]) do
        conn = log_in_as_admin(conn)
        {:ok, index_live, _html} = live(conn, ~p"/home")

        index_live
        |> element("button#create-poll-button", "New Question")
        |> render_click()

        assert index_live
               |> form("#voting-form", voting: @invalid_attrs)
               |> render_change() =~ "can&#39;t be blank"

        [title1, title2, _title3] = @suggested_titles

        assert index_live
               |> form("#voting-form", voting: @create_attrs)
               |> render_submit() =~ title1

        response =
          index_live
          |> element("button", title2)
          |> render_click()

        voting = Votings.get_voting!(title: title2)
        voting_path = ~p"/p/#{voting.slug}"

        {_, {:redirect, %{to: ^voting_path}}} = response
      end
    end
  end

  describe "Show" do
    setup [:create_voting]

    test "displays voting as logged user", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)

      {:ok, _show_live, html} = live(conn, ~p"/p/#{voting.slug}")

      assert html =~ voting.title
    end

    test "displays voting as non-logged visitor", %{conn: conn, voting: voting} do
      {:ok, _show_live, html} = live(conn, ~p"/p/#{voting.slug}")

      assert html =~ voting.title
    end

    test "updates voting within modal", %{conn: conn, voting: voting} do
      conn = log_in_as_admin(conn)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{voting.slug}")

      assert show_live
             |> element("a", "Edit")
             |> render_click() =~ "Edit Voting"

      assert_patch(show_live, ~p"/p/#{voting.slug}/show/edit")

      assert show_live
             |> form("#voting-form", voting: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#voting-form", voting: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/p/#{voting.slug}")

      html = render(show_live)
      assert html =~ "Voting updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes voting in listing", %{conn: conn, voting: voting} do
      conn = log_in_as_admin(conn)

      {:ok, index_live, _html} = live(conn, ~p"/p/#{voting.slug}/edit")

      index_live
      |> element("a", "Delete")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn ->
        Votings.get_voting!(voting.id)
      end
    end

    test "casts a vote from voting buttons", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)

      opinion = opinion_fixture(%{voting_id: voting.id})
      #  Create a vote so we display the voting options
      vote_fixture(%{voting_id: voting.id, opinion_id: opinion.id})

      {:ok, show_live, _html} = live(conn, ~p"/p/#{voting.slug}")

      #  Vote strongly agree
      show_live
      |> element("button##{voting.id}-vote-strongly-agree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Strongly agree"

      # Vote agree
      show_live
      |> element("button##{voting.id}-vote-agree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Agree"

      # Vote Abstain
      show_live
      |> element("button##{voting.id}-vote-abstain")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Abstain"

      # Vote N/A
      show_live
      |> element("button##{voting.id}-vote-na")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted N/A"

      # Vote disagree
      show_live
      |> element("button##{voting.id}-vote-disagree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Disagree"

      # Vote strongly disagree
      show_live
      |> element("button##{voting.id}-vote-strongly-disagree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Strongly disagree"
    end

    test "creates a comment", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)

      another_user = user_fixture()

      opinion = opinion_fixture(%{voting_id: voting.id})

      #  Create an AI generated comment as we don't display the form until we have one of these
      vote_fixture(%{
        twin: true,
        voting_id: voting.id,
        author_id: another_user.author_id,
        opinion_id: opinion.id
      })

      {:ok, show_live, _html} = live(conn, ~p"/p/#{voting.slug}")

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Comment created successfully"
      assert html =~ "some comment"

      # Check that the vote is N/A
      assert html =~ "N/A"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end

    test "edit a comment", %{conn: conn, voting: voting} do
      user = user_fixture()

      conn = log_in_user(conn, user)

      opinion =
        opinion_fixture(%{
          author_id: user.author_id,
          user_id: user.id,
          voting_id: voting.id,
          content: "whatever",
          twin: false
        })

      vote_fixture(%{
        voting_id: voting.id,
        author_id: user.author_id,
        opinion_id: opinion.id,
        user_id: user.id,
        twin: false
      })

      #  Create an AI generated comment as we don't display the form until we have one of these
      vote_fixture(%{twin: true, voting_id: voting.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{voting.slug}")

      assert render(show_live) =~ "whatever"

      show_live
      |> element("a", "Edit comment")
      |> render_click()

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Your comment has been updated"
      refute html =~ "whatever"
      assert html =~ "some comment"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end

    test "like icon click changes from heart.svg to filled-heart.svg", %{conn: conn} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)
      voting = voting_fixture()
      vote_fixture(%{voting_id: voting.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{voting.slug}")

      # We have a heart icon
      assert has_element?(show_live, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(show_live, "img[src='/images/filled-heart.svg']")

      # Like the opinion
      show_live
      |> element("img[src='/images/heart.svg']")
      |> render_click()

      # We have a filled heart icon
      assert has_element?(show_live, "img[src='/images/filled-heart.svg']")

      # We don't have a heart icon
      refute has_element?(show_live, "img[src='/images/heart.svg']")

      # Unlike the opinion
      show_live
      |> element("img[src='/images/filled-heart.svg']")
      |> render_click()

      # We have a heart icon
      assert has_element?(show_live, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(show_live, "img[src='/images/filled-heart.svg']")
    end

    test "filters opinions correctly", %{conn: conn, voting: voting} do
      # Create test data
      user = user_fixture()
      ai_author = author_fixture(%{twin: true})
      human_author = author_fixture(%{twin: false})

      # Create opinions with different responses and authors
      strongly_agree_ai = vote_fixture(%{
        voting_id: voting.id,
        author_id: ai_author.id,
        answer_id: Answers.answer_id_by_response("Strongly agree"),
        twin: true
      }, true)
      agree_human = vote_fixture(%{
        voting_id: voting.id,
        author_id: human_author.id,
        answer_id: Answers.answer_id_by_response("Agree"),
        twin: false
      }, true)
      disagree_ai = vote_fixture(%{
        voting_id: voting.id,
        author_id: ai_author.id,
        answer_id: Answers.answer_id_by_response("Disagree"),
        twin: true
      }, true)

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, ~p"/p/#{voting.slug}")

      # Test initial state shows all opinions
      assert html =~ "All opinions (3)"
      assert html =~ "AI (2)"
      assert html =~ "HUMAN (1)"

      # Test answer filter
      html = show_live
             |> form("form[phx-change='filter-answer']", %{"answer" => "Strongly agree"})
             |> render_change()

      assert html =~ "Strongly agree (1)"
      assert html =~ ai_author.name
      refute html =~ human_author.name

      # Select all opinions
      html = show_live
             |> form("form[phx-change='filter-answer']", %{"answer" => ""})
             |> render_change()

      # Test AI filter
      html = show_live
             |> element("span", "AI")
             |> render_click()

      assert html =~ ai_author.name
      refute html =~ human_author.name

      # Test Human filter
      html = show_live
             |> element("span", "HUMAN")
             |> render_click()

      assert html =~ human_author.name
      refute html =~ ai_author.name

      # Test combined filters
      html = show_live
             |> form("form[phx-change='filter-answer']", %{"answer" => "Agree"})
             |> render_change()

      assert html =~ human_author.name
      assert html =~ "Agree (1)"
      refute html =~ ai_author.name
    end
  end
end
