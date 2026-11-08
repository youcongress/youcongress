defmodule YouCongressWeb.PeopleListController do
  use YouCongressWeb, :controller

  def legacy(conn, %{"id" => id}) do
    case YouCongress.PeopleLists.get(id) do
      nil ->
        conn |> put_status(:not_found) |> text("This list is not available.")

      list ->
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: YouCongressWeb.PeopleListPaths.public_path(list))
    end
  end
end
