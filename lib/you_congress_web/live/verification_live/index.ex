defmodule YouCongressWeb.VerificationLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Verifications
  import YouCongressWeb.Tools.TimeAgo

  @per_page 20

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok,
     socket
     |> assign(:page_title, "Verifications")
     |> assign(:page, 1)
     |> assign(:has_more, true)
     |> load_verifications(1)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply, load_verifications(socket, socket.assigns.page + 1)}
  end

  defp load_verifications(socket, page) do
    offset = (page - 1) * @per_page

    verifications =
      Verifications.list_verifications(
        order_by: [desc: :updated_at],
        limit: @per_page,
        offset: offset,
        preload: [opinion: [:author, :statements], user: [:author]]
      )

    has_more = length(verifications) == @per_page

    socket
    |> assign(
      :verifications,
      if(page == 1,
        do: verifications,
        else: socket.assigns.verifications ++ verifications
      )
    )
    |> assign(:page, page)
    |> assign(:has_more, has_more)
  end

  defp status_badge_classes(:verified), do: "bg-green-100 text-green-800"
  defp status_badge_classes(:endorsed), do: "bg-blue-100 text-blue-800"
  defp status_badge_classes(:disputed), do: "bg-orange-100 text-orange-800"
  defp status_badge_classes(:unverifiable), do: "bg-gray-200 text-gray-600"
  defp status_badge_classes(:unverified), do: "bg-gray-100 text-gray-800"

  defp status_label(:verified), do: "Verified"
  defp status_label(:endorsed), do: "Endorsed"
  defp status_label(:disputed), do: "Disputed"
  defp status_label(:unverifiable), do: "Unverifiable"
  defp status_label(:unverified), do: "Unverified"
end
