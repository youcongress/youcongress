defmodule YouCongressWeb.TwitterLogInControllerTest do
  use YouCongressWeb.ConnCase, async: true

  import YouCongress.AccountsFixtures
  import YouCongress.InvitationsFixtures
  import Mock

  @twitter_data %ExTwitter.Model.User{
    id_str: "12022522",
    id: 12_022_522,
    screen_name: "arpahector",
    description:
      "Elixir dev\nDiscover Livebooks: https://t.co/uBK9rRtzLm\nOrganizer of Elixir meetups in Madrid: @madelixir\nPaella lover",
    location: "Madrid",
    name: "Hec Perez",
    followers_count: 968,
    verified: false,
    raw_data: %{email: "hec@whatever.com"},
    created_at: "Wed Jan 09 11:39:52 +0000 2008",
    default_profile_image: false,
    default_profile: true,
    derived: nil,
    favourites_count: 1653,
    friends_count: 1019,
    listed_count: 95,
    profile_banner_url: "https://pbs.twimg.com/profile_banners/12022522/1680877211",
    profile_image_url_https:
      "https://pbs.twimg.com/profile_images/1546550762867662850/399lTqfe_normal.jpg",
    protected: false,
    statuses_count: 2812,
    url: "https://t.co/22wFaOXtc5",
    withheld_in_countries: [],
    withheld_scope: nil
  }

  alias YouCongress.Accounts

  describe "POST /log_in" do
    test "log in with twitter", %{conn: conn} do
      conn = post(conn, ~p"/log_in")
      assert redirected_to(conn) =~ "https://api.twitter.com/oauth/authenticate"
    end
  end

  describe "GET /twitter-callback" do
    test "redirects to /waiting_list if NO user and NOT in invitation list", %{
      conn: conn
    } do
      with_mocks([
        {YouCongressWeb.TwitterLogInController, [:passthrough],
         [get_callback_data: fn _, _ -> @twitter_data end]}
      ]) do
        conn = get(conn, ~p"/twitter-callback?oauth_token=one&oauth_verifier=two")
        assert user = Accounts.get_user_by_username("arpahector")
        assert user.role == "waiting_list"
        assert redirected_to(conn) =~ ~p"/waiting_list"
      end
    end

    test "redirects to /waiting_list if user in waiting list and NOT in invitation list", %{
      conn: conn
    } do
      user_fixture(%{role: "waiting_list"}, %{twitter_username: "arpahector"})

      with_mocks([
        {YouCongressWeb.TwitterLogInController, [:passthrough],
         [get_callback_data: fn _, _ -> @twitter_data end]}
      ]) do
        conn = get(conn, ~p"/twitter-callback?oauth_token=one&oauth_verifier=two")
        assert Accounts.count() == 1
        assert user = Accounts.get_user_by_username("arpahector")
        assert user.role == "waiting_list"
        assert redirected_to(conn) =~ ~p"/waiting_list"
      end
    end

    test "redirects to /welcome if user in waiting list and in invitation list", %{
      conn: conn
    } do
      user_fixture(%{role: "waiting_list"}, %{twitter_username: "arpahector"})
      invitation_fixture(%{twitter_username: "arpahector"})

      with_mocks([
        {YouCongressWeb.TwitterLogInController, [:passthrough],
         [get_callback_data: fn _, _ -> @twitter_data end]}
      ]) do
        conn = get(conn, ~p"/twitter-callback?oauth_token=one&oauth_verifier=two")
        assert Accounts.count() == 1
        assert user = Accounts.get_user_by_username("arpahector")
        assert user.role == "user"
        assert redirected_to(conn) =~ ~p"/welcome"
      end
    end

    test "redirects to /welcome if user NOT in waiting list and in invitation list", %{
      conn: conn
    } do
      invitation_fixture(%{twitter_username: "arpahector"})

      with_mocks([
        {YouCongressWeb.TwitterLogInController, [:passthrough],
         [get_callback_data: fn _, _ -> @twitter_data end]}
      ]) do
        conn = get(conn, ~p"/twitter-callback?oauth_token=one&oauth_verifier=two")
        assert Accounts.count() == 1
        assert user = Accounts.get_user_by_username("arpahector")
        assert user.role == "user"
        assert redirected_to(conn) =~ ~p"/welcome"
      end
    end

    test "redirects to /home if returning user", %{
      conn: conn
    } do
      user_fixture(%{role: "user"}, %{twitter_username: "arpahector"})

      with_mocks([
        {YouCongressWeb.TwitterLogInController, [:passthrough],
         [get_callback_data: fn _, _ -> @twitter_data end]}
      ]) do
        conn = get(conn, ~p"/twitter-callback?oauth_token=one&oauth_verifier=two")
        assert Accounts.count() == 1
        assert user = Accounts.get_user_by_username("arpahector")
        assert user.role == "user"
        assert redirected_to(conn) =~ ~p"/home"
      end
    end

    test "redirects to /welcome if returning user in invitation list", %{
      conn: conn
    } do
      user_fixture(%{role: "user"}, %{twitter_username: "arpahector"})
      invitation_fixture(%{twitter_username: "arpahector"})

      with_mocks([
        {YouCongressWeb.TwitterLogInController, [:passthrough],
         [get_callback_data: fn _, _ -> @twitter_data end]}
      ]) do
        conn = get(conn, ~p"/twitter-callback?oauth_token=one&oauth_verifier=two")
        assert Accounts.count() == 1
        assert user = Accounts.get_user_by_username("arpahector")
        assert user.role == "user"
        assert redirected_to(conn) =~ ~p"/welcome"
      end
    end
  end
end
