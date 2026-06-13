defmodule YouCongressWeb.Components.VerificationBadgeTest do
  use YouCongressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias YouCongress.Accounts.User
  alias YouCongress.Opinions.Opinion
  alias YouCongressWeb.Components.VerificationBadge

  defp moderator, do: %User{id: 1, role: "moderator", author_id: 99}
  defp user, do: %User{id: 2, role: "user", author_id: nil}

  defp render_badge(assigns) do
    defaults = %{
      id: "verification-badge-test",
      opinion: %Opinion{id: 42, author_id: 2, verification_status: :verified},
      current_user: moderator()
    }

    render_component(VerificationBadge, Map.merge(defaults, assigns))
  end

  test "link mode sends permitted users to the opinion page instead of opening the editor" do
    html = render_badge(%{link_to_opinion: true})

    assert html =~ ~s|href="/c/42"|
    refute html =~ ~s|phx-click="toggle-dropdown"|
    refute html =~ "/faq#verify-quotes"
  end

  test "link mode sends non-permitted users to the opinion page instead of the FAQ" do
    html = render_badge(%{current_user: user(), link_to_opinion: true})

    assert html =~ ~s|href="/c/42"|
    refute html =~ "/faq#verify-quotes"
  end

  test "default mode keeps permitted users on the inline editor trigger" do
    html = render_badge(%{})

    assert html =~ ~s|phx-click="toggle-dropdown"|
    refute html =~ ~s|href="/c/42"|
  end
end
