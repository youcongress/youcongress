defmodule YouCongressWeb.AuthorPaths do
  @moduledoc "Profile destinations using a YouCongress username or author ID."
  use YouCongressWeb, :verified_routes

  def profile(%{username: username}) when is_binary(username) and username != "",
    do: ~p"/@#{username}"

  def profile(%{id: id}), do: ~p"/a/#{id}"

  def trust(author), do: profile(author) <> "/trust"
  def lists(author), do: profile(author) <> "/lists"
end
