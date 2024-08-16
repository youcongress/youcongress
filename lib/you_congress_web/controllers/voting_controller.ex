defmodule YouCongressWeb.VotingController do
  use YouCongressWeb, :controller

  def redirect_to_p(conn, %{"slug" => slug}) do
    redirect(conn, to: ~p"/p/#{slug}")
  end
end
