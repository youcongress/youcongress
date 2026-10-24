defmodule YouCongressWeb.RouterSecurityTest do
  use YouCongressWeb.ConnCase, async: true

  alias Phoenix.LiveView.Route
  alias Phoenix.LiveView.Socket
  alias YouCongressWeb.AuthorLive
  alias YouCongressWeb.Endpoint
  alias YouCongressWeb.Router
  alias YouCongressWeb.StatementLive

  test "admin edit routes cross the public LiveView session boundary" do
    public_socket = %Socket{
      endpoint: Endpoint,
      router: Router,
      private: %{live_session_name: :default}
    }

    assert {:external, %URI{path: "/p/example/show/edit"}} =
             Route.live_link_info!(
               public_socket,
               StatementLive.Show,
               "/p/example/show/edit"
             )

    assert {:external, %URI{path: "/authors/123/show/edit"}} =
             Route.live_link_info!(
               public_socket,
               AuthorLive.Show,
               "/authors/123/show/edit"
             )
  end
end
