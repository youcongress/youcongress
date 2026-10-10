defmodule YouCongressWeb.MolochLiveTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "public page has crawler metadata, educational content and proposal links", %{conn: conn} do
    html = conn |> get(~p"/moloch") |> html_response(200)
    document = Floki.parse_document!(html)

    assert Floki.text(Floki.find(document, "h1")) =~ "Moloch: Why We Race"

    assert Floki.attribute(document, "link[rel=canonical]", "href") ==
             [YouCongressWeb.Endpoint.url() <> "/moloch"]

    assert Floki.attribute(document, "meta[name=description]", "content") |> hd() =~
             "coordination failures"

    assert Floki.attribute(document, "meta[property='og:url']", "content") ==
             [YouCongressWeb.Endpoint.url() <> "/moloch"]

    assert html =~ "Revealing agreement is not the same as solving a coordination problem."
    assert html =~ "not commitment infrastructure that YouCongress offers today"
    assert length(Floki.find(document, "#proposals a[href^='/p/']")) == 4
    assert Floki.find(document, "button[data-copy-url='/moloch']") != []
    assert Floki.find(document, "footer a[href='/moloch']") != []
  end

  test "all four scenarios update lab outcomes and accessible selection state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/moloch")
    assert has_element?(view, "#race-outcome", "Stronger safeguards")
    assert has_element?(view, "#lab-a-safety[aria-pressed=true]")
    assert has_element?(view, "#lab-b-safety[aria-pressed=true]")

    view |> element("#lab-a-speed") |> render_click()
    assert has_element?(view, "#race-outcome", "Lab A may pull ahead. Lab B feels the pressure.")
    assert has_element?(view, "#race-outcome dl > div:first-child", "head start")
    assert has_element?(view, "#lab-a-speed[aria-pressed=true]")
    assert has_element?(view, "#lab-a-safety[aria-pressed=false]")

    view |> element("#lab-b-speed") |> render_click()
    assert has_element?(view, "#race-outcome", "A faster race. No clear relative winner.")

    view |> element("#lab-a-safety") |> render_click()
    assert has_element?(view, "#race-outcome", "Lab B may pull ahead. Lab A feels the pressure.")
    assert has_element?(view, "#race-outcome dl > div:first-child", "lose ground")
    assert has_element?(view, "#race-outcome dl > div:nth-child(2)", "head start")

    view |> element("#lab-b-safety") |> render_click()

    assert has_element?(
             view,
             "#race-outcome[aria-live=polite][aria-atomic=true]",
             "Stronger safeguards"
           )
  end

  test "invalid choice events leave the scenario unchanged", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/moloch")
    render_click(view, "choose", %{"lab" => "unknown", "choice" => "speed"})
    render_click(view, "choose", %{"lab" => "a", "choice" => "unknown"})
    render_click(view, "choose", %{})
    assert has_element?(view, "#lab-a-safety[aria-pressed=true]")
    assert has_element?(view, "#lab-b-safety[aria-pressed=true]")
  end
end
