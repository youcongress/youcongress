defmodule YouCongressWeb.SimController do
  use YouCongressWeb, :controller
  import Phoenix.Controller

  def index(conn, _params) do
    conn
    |> put_root_layout(false)
    |> render(:index, layout: false)
  end
end
