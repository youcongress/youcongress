defmodule YouCongressWeb.SimController do
  use YouCongressWeb, :controller

  def index(conn, _params) do
    render(conn, :index, layout: false)
  end
end
