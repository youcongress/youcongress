defmodule YouCongressWeb.AiPolicyLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest

  alias YouCongress.Accounts
  alias YouCongress.AccountsFixtures
  alias YouCongress.CountriesFixtures
  alias YouCongress.Repo

  test "renders the AI Policy Group page and account registration fields", %{conn: conn} do
    _country = CountriesFixtures.country_fixture(name: "AI Page Country")

    {:ok, _view, html} = live(conn, ~p"/ai")

    assert html =~ "100 AI Policies"
    assert html =~ "Create account &amp; register interest"
    assert html =~ "AI Page Country"
    assert html =~ "/auth/google?return_to=%2Fai%3Ffrom%3Dgoogle%23register"
  end

  test "a user coming back from Google sees a flash pointing to the Join us section", %{
    conn: conn
  } do
    user = AccountsFixtures.user_fixture() |> Repo.preload(:author)

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/ai?from=google")

    assert html =~ "Logged in with Google. Now you can register your interest."
  end

  test "the Google flash is not shown to logged out visitors", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/ai?from=google")

    refute html =~ "Logged in with Google"
  end

  test "a signed-in user sees their name prefilled and a link to settings", %{conn: conn} do
    country = CountriesFixtures.country_fixture(name: "Prefilled AI Country")

    user =
      AccountsFixtures.user_fixture(%{}, %{name: "Prefilled Participant", country_id: country.id})
      |> Repo.preload(:author)

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/ai")

    assert html =~ "Prefilled Participant"
    assert html =~ "Change your name in settings"
    assert html =~ ~s(href="/settings")
  end

  test "a signed-in user updates country and AI signup context", %{conn: conn} do
    initial_country = CountriesFixtures.country_fixture(name: "Initial AI Country")
    selected_country = CountriesFixtures.country_fixture(name: "Selected AI Country")

    user =
      AccountsFixtures.user_fixture(%{}, %{
        name: "Initial AI Participant",
        country_id: initial_country.id
      })
      |> Repo.preload(:author)

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/ai")

    view
    |> form("#ai-policy-registration",
      signup: %{
        "country_id" => selected_country.id,
        "professional_background" => "policy",
        "linkedin_or_website" => "linkedin.com/in/ai-participant",
        "interests" => ["governance", "jobs"],
        "availability_and_motivation" => "Weekday evenings"
      }
    )
    |> render_submit()

    updated_user = Repo.get!(Accounts.User, user.id)
    updated_author = Repo.get!(YouCongress.Authors.Author, user.author_id)

    assert updated_author.country_id == selected_country.id

    assert updated_user.sign_up_context == %{
             "campaign" => "ai_policy_group",
             "professional_background" => "policy",
             "linkedin_or_website" => "linkedin.com/in/ai-participant",
             "interests" => ["governance", "jobs"],
             "availability_and_motivation" => "Weekday evenings"
           }
  end

  test "new AI registrations persist the country on the author and the context on the user" do
    country = CountriesFixtures.country_fixture(name: "New AI Registration Country")

    {:ok, %{user: user, author: author}} =
      Accounts.register_ai_policy_user(
        %{"email" => AccountsFixtures.unique_user_email(), "password" => "a secure password"},
        %{
          "name" => "AI Participant",
          "country_id" => country.id,
          "professional_background" => "tech",
          "linkedin_or_website" => "https://example.com/ai-participant",
          "interests" => ["competitiveness"],
          "availability_and_motivation" => "I can join monthly."
        }
      )

    assert author.country_id == country.id
    assert user.sign_up_context["professional_background"] == "tech"
    assert user.sign_up_context["interests"] == ["competitiveness"]
    assert user.sign_up_context["linkedin_or_website"] == "https://example.com/ai-participant"
  end
end
