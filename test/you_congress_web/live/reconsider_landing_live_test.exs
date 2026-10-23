defmodule YouCongressWeb.ReconsiderLandingLiveTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "explains Reconsider and links directly to its creation page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reconsider")

    assert html =~ "Discover whether your content changes minds"
    assert html =~ "policy proposals or claims"
    assert html =~ "Ready when you are"
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
    # The progress bar width is a Tailwind class, not an inline style, so the
    # Content Security Policy can keep style-src free of 'unsafe-inline'.
    assert has_element?(view, "#example-change-bar div.w-3\\/4")

    assert has_element?(view, "#reconsider-results-example", "14 participants (23%)")
    assert has_element?(view, "#reconsider-results-example", "9 participants (15%)")
    assert has_element?(view, "#reconsider-results-example div.text-4xl", "75%")
    refute has_element?(view, "#reconsider-results-example p.text-4xl", "75%")

    create_path = ~p"/reconsider/new"

    assert has_element?(view, "#reconsider-motion-ad[phx-hook='ReconsiderMotionAd']")
    assert has_element?(view, "#reconsider-motion-ad [data-ad-scene]", "You hit publish.")

    assert has_element?(
             view,
             "#reconsider-motion-ad [data-ad-scene]",
             "Step 4 · See how minds moved"
           )

    assert has_element?(
             view,
             "#reconsider-motion-ad [data-ad-replay][aria-label='Replay from the start']"
           )

    assert has_element?(
             view,
             "#reconsider-motion-ad [data-ad-toggle][aria-label='Pause animation']"
           )

    assert has_element?(
             view,
             "#reconsider-motion-ad a[href='#{create_path}']",
             "Create a Reconsider page"
           )

    assert has_element?(
             view,
             "#reconsider-create[href='#{create_path}']",
             "Create a Reconsider page"
           )

    assert has_element?(
             view,
             "#reconsider-create-secondary[href='#{create_path}']",
             "Create a Reconsider page"
           )

    refute html =~ "Ask to try"
    refute html =~ "Contact YouCongress"
  end
end
