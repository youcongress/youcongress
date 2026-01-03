# defmodule YouCongressWeb.ActivityLiveTest do
#   use YouCongressWeb.ConnCase
#
#   import Phoenix.LiveViewTest
#   import YouCongress.AuthorsFixtures
#   import YouCongress.OpinionsFixtures
#   import YouCongress.StatementsFixtures
#   import YouCongress.AccountsFixtures
#
#   alias YouCongress.Opinions
#
#   describe "Index" do
#     test "lists recent opinions", %{conn: conn} do
#       author1 = author_fixture(%{name: "Someone1"})
#
#       voting = statement_fixture(%{author_id: author1.id})
#
#       opinion1 =
#         opinion_fixture(%{
#           author_id: author1.id,
#           content: "Opinion1",
#           twin: true
#         })
#
#       author2 = author_fixture(%{name: "Someone2"})
#
#       opinion2 =
#         opinion_fixture(%{
#           author_id: author2.id,
#           content: "Opinion2",
#           twin: true
#         })
#
#       opinion3 =
#         opinion_fixture(%{
#           author_id: author2.id,
#           content: "Opinion3",
#           ancestry: "#{opinion2.id}",
#           twin: false
#         })
#
#       Opinions.add_opinion_to_voting(opinion1, voting)
#       Opinions.add_opinion_to_voting(opinion2, voting)
#       Opinions.add_opinion_to_voting(opinion3, voting)
#
#       {:ok, index_live, _html} = live(conn, ~p"/home")
#
#       # Toggle switch to include AI twins so we can see all opinions
#       index_live
#       |> element("button[phx-click='toggle-switch']")
#       |> render_click()
#
#       html = render(index_live)
#
#       assert html =~ opinion1.content
#       assert html =~ opinion2.content
#       assert html =~ author1.name
#       assert html =~ author2.name
#       assert html =~ opinion3.content
#     end
#
#     test "like icon click changes from heart.svg to filled-heart.svg", %{conn: conn} do
#       current_user = user_fixture()
#       conn = log_in_user(conn, current_user)
#       voting = statement_fixture()
#       opinion = opinion_fixture(%{twin: false})
#       Opinions.add_opinion_to_voting(opinion, voting)
#
#       {:ok, view, _html} = live(conn, "/home")
#
#       # We have a heart icon
#       assert has_element?(view, "img[src='/images/heart.svg']")
#
#       # We don't have a filled heart icon
#       refute has_element?(view, "img[src='/images/filled-heart.svg']")
#
#       # Like the opinion
#       view
#       |> element("img[src='/images/heart.svg']")
#       |> render_click()
#
#       # We have a filled heart icon
#       assert has_element?(view, "img[src='/images/filled-heart.svg']")
#
#       # We don't have a heart icon
#       refute has_element?(view, "img[src='/images/heart.svg']")
#
#       # Unlike the opinion
#       view
#       |> element("img[src='/images/filled-heart.svg']")
#       |> render_click()
#
#       # We have a heart icon
#       assert has_element?(view, "img[src='/images/heart.svg']")
#
#       # We don't have a filled heart icon
#       refute has_element?(view, "img[src='/images/filled-heart.svg']")
#     end
#   end
# end
