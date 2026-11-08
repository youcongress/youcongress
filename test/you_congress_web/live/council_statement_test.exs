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
      for answer <- [:for, :for, :against, :abstain, nil] do
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
             "#statement-vote-controls details:not([open]) summary",
             "See how your Council voted"
           )

    for {person, answer} <- people do
      if answer do
        assert has_element?(
                 view,
                 "#statement-council-#{answer} a[href='/a/#{person.id}']",
                 person.name
               )
      else
        refute has_element?(view, "#statement-council a[href='/a/#{person.id}']")
      end
    end

    assert has_element?(view, "#statement-council-for-heading", "(2)")
    assert has_element?(view, "#statement-council-against-heading", "(1)")
    assert has_element?(view, "#statement-council-abstain-heading", "(1)")
    assert has_element?(view, "#statement-council", "1 member has no eligible position")

    view |> element("#cast-vote-against") |> render_click()
    refute has_element?(view, "#statement-council")
    assert Councils.explain(user.author_id, statement.id).effective == :against

    view
    |> element("#statement-vote-controls .hidden button[phx-click=delete-direct-vote]")
    |> render_click()

    assert has_element?(
             view,
             "#statement-council-breakdown summary",
             "See how your Council voted"
           )
  end

  test "a tied Council does not show a Council vote breakdown", %{conn: conn} do
    user = user_fixture()
    statement = statement_fixture()

    for answer <- [:for, :against] do
      person = author_fixture()
      vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: answer})
      {:ok, _} = Councils.add_member(user, person.id)
    end

    {:ok, view, html} = live(log_in_user(conn, user), "/p/#{statement.slug}")
    refute html =~ "YouCongress Trust 30"
    refute has_element?(view, "#statement-council")
    assert Councils.explain(user.author_id, statement.id).answer == nil
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
