defmodule YouCongressWeb.AiPolicyLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest

  alias YouCongress.Accounts
  alias YouCongress.AccountsFixtures
  alias YouCongress.CountriesFixtures
  alias YouCongress.Repo

  test "renders the AI working groups page and account registration fields", %{conn: conn} do
    _country = CountriesFixtures.country_fixture(name: "AI Page Country")

    {:ok, _view, html} = live(conn, ~p"/ai")

    assert html =~ "100 AI Policies"
    assert html =~ "Create account &amp; find my group"
    assert html =~ "Send me occasional emails about features and content"
    assert html =~ "AI Page Country"
    assert html =~ "Private preview"
    assert html =~ "before Tuesday, September 8"
    assert html =~ "Personal invitations are welcome"
    assert html =~ "AI is changing society before society has chosen the rules"
    assert html =~ "Most people will"
    assert html =~ "AI policy is too important to leave only to a few governments"
    assert html =~ "Small working groups, concrete outcomes"
    assert html =~ "Shape policy"
    assert html =~ "Build the commons"
    assert html =~ "Build political influence"
    assert html =~ "How would you like to contribute?"
    assert html =~ "Improve YouCongress"
    assert html =~ "Reach policymakers and civic organizations"
    refute html =~ "Sep 2026"
    refute html =~ "Sweden"
    assert html =~ "/auth/google?return_to=%2Fai%3Ffrom%3Dgoogle%23register"
    assert html =~ "/auth/x?return_to=%2Fai%3Ffrom%3Dx%23register"
    assert html =~ ~s(rel="canonical" href="#{YouCongressWeb.Endpoint.url()}/ai")
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

  test "a user coming back from X sees a flash pointing to the Join us section", %{conn: conn} do
    user = AccountsFixtures.user_fixture() |> Repo.preload(:author)

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/ai?from=x")

    assert html =~ "Logged in with X. Now you can register your interest."
  end

  test "the X flash is not shown to logged out visitors", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/ai?from=x")

    refute html =~ "Logged in with X"
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
        "contribution_areas" => ["policy", "research", "outreach"],
        "availability_and_motivation" => "Weekday evenings",
        "newsletter" => "true"
      }
    )
    |> render_submit()

    updated_user = Repo.get!(Accounts.User, user.id)
    updated_author = Repo.get!(YouCongress.Authors.Author, user.author_id)

    assert updated_author.country_id == selected_country.id
    assert updated_user.newsletter

    assert updated_user.sign_up_context == %{
             "campaign" => "ai_policy_group",
             "professional_background" => "policy",
             "linkedin_or_website" => "linkedin.com/in/ai-participant",
             "interests" => ["governance", "jobs"],
             "contribution_areas" => ["policy", "research", "outreach"],
             "availability_and_motivation" => "Weekday evenings"
           }
  end

  test "a new account is logged in and sent to the email confirmation step", %{conn: conn} do
    country = CountriesFixtures.country_fixture(name: "Confirmation AI Country")
    email = AccountsFixtures.unique_user_email()

    {:ok, view, _html} = live(conn, ~p"/ai")

    html =
      view
      |> form("#ai-policy-registration",
        signup: %{
          "name" => "AI Participant",
          "email" => email,
          "password" => "a secure password",
          "country_id" => country.id,
          "newsletter" => "true"
        }
      )
      |> render_submit()

    assert_push_event(view, "session-login", %{
      token: token,
      redirect_to: "/sign_up?return_to=%2Fai-welcome",
      return_to: "/ai-welcome"
    })

    assert {:ok, user} = Accounts.consume_live_login_token(token)
    assert user.email == email
    assert user.newsletter
    assert is_nil(user.email_confirmed_at)

    assert html =~ "Taking you to the confirmation step"

    {:ok, _view, sign_up_html} =
      conn |> log_in_user(user) |> live(~p"/sign_up?return_to=%2Fai-welcome")

    assert sign_up_html =~ "Enter your confirmation code"
  end

  test "a logged-in user with a confirmed email is sent to /ai-welcome", %{
    conn: conn
  } do
    country = CountriesFixtures.country_fixture(name: "Confirmed AI Country")

    user =
      AccountsFixtures.user_fixture(%{}, %{name: "Confirmed Participant"})
      |> Repo.preload(:author)

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/ai")

    view
    |> form("#ai-policy-registration", signup: %{"country_id" => country.id})
    |> render_submit()

    refute_push_event(view, "session-login", %{})
    assert_redirect(view, ~p"/ai-welcome")
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
          "contribution_areas" => ["platform", "communications"],
          "availability_and_motivation" => "I can join monthly.",
          "newsletter" => "false"
        }
      )

    assert author.country_id == country.id
    assert user.sign_up_context["professional_background"] == "tech"
    assert user.sign_up_context["interests"] == ["competitiveness"]
    assert user.sign_up_context["contribution_areas"] == ["platform", "communications"]
    assert user.sign_up_context["linkedin_or_website"] == "https://example.com/ai-participant"
    refute user.newsletter
  end

  test "a signed-in user can opt out of the newsletter", %{conn: conn} do
    country = CountriesFixtures.country_fixture(name: "Opt Out AI Country")

    user =
      AccountsFixtures.user_fixture(%{}, %{name: "Subscribed Participant"})
      |> Repo.preload(:author)

    {:ok, user} = Accounts.welcome_update(user, %{"newsletter" => true})

    {:ok, view, html} = conn |> log_in_user(user) |> live(~p"/ai")

    assert html =~ ~s(name="signup[newsletter]" value="true" checked)

    view
    |> form("#ai-policy-registration",
      signup: %{"country_id" => country.id, "newsletter" => "false"}
    )
    |> render_submit()

    refute Repo.get!(Accounts.User, user.id).newsletter
  end
end
