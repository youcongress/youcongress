defmodule YouCongressWeb.CouncilStatementTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.Councils

  test "Council votes have a collapsed breakdown below the buttons, grouped by answer", %{
    conn: conn
  } do
    user = user_fixture()
    statement = statement_fixture()

    people =
      for answer <- [:for, :for, :for, :for, :against, :abstain, nil] do
        person = author_fixture()

        if answer,
          do: vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: answer})

        {:ok, _} = Councils.add_member(user, person.id)
        {person, answer}
      end

    {:ok, view, html} = live(log_in_user(conn, user), "/p/#{statement.slug}")
    refute html =~ "YouCongress Trust 30"
    refute has_element?(view, "#my-council-decision")
    assert has_element?(view, "#statement-vote-controls", "via your Council")

    assert has_element?(
             view,
             "#statement-vote-controls #statement-council-toggle[aria-expanded=false]",
             "See how your Council voted"
           )

    assert has_element?(view, "#statement-council-breakdown[hidden]")
    refute has_element?(view, "#statement-vote-controls #statement-council-breakdown")
    view |> element("#statement-council-toggle") |> render_click()
    assert has_element?(view, "#statement-council-breakdown:not([hidden])")
    assert has_element?(view, "#statement-council-toggle[aria-expanded=true]")
    view |> element("#statement-council-toggle") |> render_click()
    assert has_element?(view, "#statement-council-breakdown[hidden]")

    for {person, _answer} <- people do
      assert has_element?(view, "#statement-council a[href='/a/#{person.id}']", person.name)
    end

    assert has_element?(view, "#statement-council h4", "For (4)")
    assert has_element?(view, "#statement-council h4", "Against (1)")
    assert has_element?(view, "#statement-council h4", "Abstain (1)")
    assert has_element?(view, "#statement-council h4", "No position (1)")
    assert has_element?(view, "#statement-council", "3 of 5 For or Against positions needed")
    assert has_element?(view, "#statement-council", "Skipped · Not a matching hall")

    view |> element("#cast-vote-against") |> render_click()
    refute has_element?(view, "#statement-council")
    assert Councils.explain(user.author_id, statement.id).effective == :against

    view
    |> element("#statement-vote-controls .hidden button[phx-click=delete-direct-vote]")
    |> render_click()

    assert has_element?(
             view,
             "#statement-council-toggle",
             "See how your Council voted"
           )
  end

  test "a tied Council explains why no vote was cast", %{conn: conn} do
    user = user_fixture()
    statement = statement_fixture()

    for answer <- [:for, :against] do
      person = author_fixture()
      vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: answer})
      {:ok, _} = Councils.add_member(user, person.id)
    end

    {:ok, view, html} = live(log_in_user(conn, user), "/p/#{statement.slug}")
    refute html =~ "YouCongress Trust 30"
    assert has_element?(view, "#statement-vote-controls", "Your Council has no majority")

    assert has_element?(
             view,
             "#statement-council-toggle",
             "See how your Council voted"
           )

    assert Councils.explain(user.author_id, statement.id).answer == nil
  end

  for majority? <- [true, false] do
    @majority? majority?
    test "clearing a pre-existing direct vote restores Council status (majority: #{majority?})",
         %{
           conn: conn
         } do
      user = user_fixture()
      statement = statement_fixture()
      person = author_fixture()
      {:ok, _} = Councils.add_member(user, person.id)

      if @majority? do
        vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
      end

      {:ok, _} =
        YouCongress.Votes.create_or_update(%{
          author_id: user.author_id,
          statement_id: statement.id,
          answer: :against,
          direct: true
        })

      {:ok, view, _} = live(log_in_user(conn, user), "/p/#{statement.slug}")
      refute has_element?(view, "#statement-council")

      view
      |> element("#statement-vote-controls .hidden button[phx-click=delete-direct-vote]")
      |> render_click()

      assert has_element?(
               view,
               "#statement-council-toggle",
               "See how your Council voted"
             )

      refute has_element?(view, "button[phx-click=delete-direct-vote]")

      if @majority? do
        assert has_element?(view, "#statement-vote-controls", "via your Council")
        assert has_element?(view, "#statement-council", "Sets your vote: For")

        assert YouCongress.Votes.get_current_user_vote(statement.id, user.author_id).answer ==
                 :for
      else
        assert has_element?(view, "#statement-vote-controls", "No vote has been cast for you")
        assert has_element?(view, "#statement-council h4", "No position (1)")
        assert is_nil(YouCongress.Votes.get_current_user_vote(statement.id, user.author_id))
      end
    end
  end

  test "visitors and participants without a Council vote see only the voting controls", %{
    conn: conn
  } do
    statement = statement_fixture()
    {:ok, guest, html} = live(conn, "/p/#{statement.slug}")
    refute html =~ "YouCongress Trust 30"
    refute has_element?(guest, "#statement-council")
    assert has_element?(guest, "#cast-vote-for")
    {:ok, member, _} = live(log_in_user(conn, user_fixture()), "/p/#{statement.slug}")
    refute has_element?(member, "#statement-council")
  end
end
