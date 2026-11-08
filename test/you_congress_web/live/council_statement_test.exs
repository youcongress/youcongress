defmodule YouCongressWeb.CouncilStatementTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.Councils

  test "statement explains Council majority and updates after a direct override", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    {:ok, _} = Councils.add_member(user, person.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/p/#{statement.slug}")
    assert has_element?(view, "#my-council-decision h2", "For")
    assert has_element?(view, "#my-council-decision", "via your Council")
    assert has_element?(view, "#my-council-decision", person.name)
    view |> element("#cast-vote-against") |> render_click()
    assert has_element?(view, "#my-council-decision h2", "Against")
    assert has_element?(view, "#my-council-decision", "your direct vote")
    assert Councils.explain(user.author_id, statement.id).effective == :against
  end

  test "a tied Council does not cast a vote", %{conn: conn} do
    user = user_fixture()
    statement = statement_fixture()

    for answer <- [:for, :against] do
      person = author_fixture()
      vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: answer})
      {:ok, _} = Councils.add_member(user, person.id)
    end

    {:ok, view, _} = live(log_in_user(conn, user), "/p/#{statement.slug}")
    assert has_element?(view, "#my-council-decision", "No Council vote is cast")
    assert Councils.explain(user.author_id, statement.id).answer == nil
  end
end
