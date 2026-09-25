defmodule YouCongressWeb.ReconsiderLandingLiveTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @contact_subject "Reconsider beta access"
  @contact_body """
  Hi YouCongress team,

  I'd like to try Reconsider for an article or video.

  My publication or channel:
  Link:
  What I'd like to test:
  """

  test "explains Reconsider and links to a prefilled beta request", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reconsider")

    assert html =~ "Discover whether your content changes minds"
    assert html =~ "Currently in beta"
    assert html =~ "How it works"

    contact_path = ~p"/contact?#{%{subject: @contact_subject, body: @contact_body}}"

    assert has_element?(
             view,
             "#reconsider-beta-contact[href='#{contact_path}']",
             "Ask to try Reconsider"
           )
  end
end
