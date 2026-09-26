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
    assert html =~ "policy proposals or claims"
    assert html =~ "Currently in beta"
    assert html =~ "How it works"
    assert has_element?(view, "#reconsider-example", "See a Reconsider page in action")

    assert has_element?(
             view,
             "#reconsider-voting-example",
             "Before this video"
           )

    assert has_element?(view, "#example-video-link", "Watch the original video")
    assert has_element?(view, "#example-delegate-energy-expert", "Dr. Maya Chen")

    assert has_element?(
             view,
             "#example-delegate-policy-researcher",
             "Alex Rivera"
           )

    assert has_element?(
             view,
             "#reconsider-results-example",
             "75% of 60 participants changed their position."
           )

    assert has_element?(view, "#example-change-bar", "75% reported changing 60 completed")
    assert has_element?(view, "#example-change-bar div[style='width: 75%']")

    assert has_element?(view, "#reconsider-results-example", "14 participants (23%)")
    assert has_element?(view, "#reconsider-results-example", "9 participants (15%)")

    contact_path = ~p"/contact?#{%{subject: @contact_subject, body: @contact_body}}"

    assert has_element?(
             view,
             "#reconsider-beta-contact[href='#{contact_path}']",
             "Ask to try Reconsider"
           )
  end
end
