defmodule YouCongressWeb.Components.VerificationBadge do
  @moduledoc """
  A reusable LiveComponent for displaying and managing opinion verification status.

  For logged-in users, it renders a clickable badge with a dropdown to select status.
  For non-logged-in users, it renders a static link to the FAQ.
  """

  use YouCongressWeb, :live_component

  alias YouCongress.Accounts.Permissions
  alias YouCongress.Verifications

  @statuses ~w(verified disputed unverifiable unverified)a

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:opinion, assigns.opinion)
     |> assign(:current_user, assigns[:current_user])
     |> assign(:class, assigns[:class] || "ml-2")
     |> assign_new(:show_dropdown, fn -> false end)
     |> assign_new(:selected_status, fn -> nil end)
     |> assign_new(:comment, fn -> "" end)}
  end

  def render(assigns) do
    ~H"""
    <span class={[@class, "relative inline-block"]}>
      <%= if @current_user && Permissions.can_verify_opinion?(@current_user) do %>
        <span
          class={[
            "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium cursor-pointer",
            badge_classes(@opinion.verification_status)
          ]}
          phx-click="toggle-dropdown"
          phx-target={@myself}
        >
          {badge_label(@opinion.verification_status)}
        </span>
        <%= if @show_dropdown do %>
          <div class="absolute z-10 bottom-full mb-1 bg-white border rounded shadow-lg left-0">
            <%= if @selected_status do %>
              <div class="p-2 w-56">
                <div class={["text-xs font-medium mb-1", badge_text_class(@selected_status)]}>
                  {badge_label(@selected_status)}
                </div>
                <input
                  id={"verification-comment-#{@opinion.id}"}
                  type="text"
                  placeholder="Comment (optional)"
                  value={@comment}
                  phx-keyup="update-comment"
                  phx-target={@myself}
                  phx-mounted={JS.focus()}
                  class="w-full text-xs border rounded px-2 py-1 mb-2"
                />
                <div class="flex gap-1">
                  <button
                    phx-click="confirm-status"
                    phx-target={@myself}
                    class="flex-1 text-xs px-2 py-1 bg-indigo-600 text-white rounded hover:bg-indigo-700"
                  >
                    Save
                  </button>
                  <button
                    phx-click="cancel-status"
                    phx-target={@myself}
                    class="flex-1 text-xs px-2 py-1 bg-gray-200 text-gray-700 rounded hover:bg-gray-300"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            <% else %>
              <div class="w-40">
                <%= for status <- statuses_for(@opinion, @current_user) do %>
                  <button
                    phx-click="pick-status"
                    phx-value-status={status}
                    phx-target={@myself}
                    class={[
                      "block w-full text-left px-3 py-1.5 text-xs hover:bg-gray-100",
                      badge_text_class(status)
                    ]}
                  >
                    {badge_label(status)}
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      <% else %>
        <Phoenix.Component.link
          href="/faq#verify-quotes"
          class={[
            "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium",
            badge_classes(@opinion.verification_status)
          ]}
        >
          {badge_label(@opinion.verification_status)}
        </Phoenix.Component.link>
      <% end %>
    </span>
    """
  end

  def handle_event("toggle-dropdown", _, socket) do
    show = !socket.assigns.show_dropdown

    {:noreply,
     socket
     |> assign(:show_dropdown, show)
     |> assign(:selected_status, nil)
     |> assign(:comment, "")}
  end

  def handle_event("pick-status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:selected_status, String.to_existing_atom(status))
     |> assign(:comment, "")}
  end

  def handle_event("update-comment", %{"key" => "Enter", "value" => value}, socket) do
    {:noreply, socket |> assign(:comment, value) |> confirm_status()}
  end

  def handle_event("update-comment", %{"value" => value}, socket) do
    {:noreply, assign(socket, :comment, value)}
  end

  def handle_event("confirm-status", _, socket) do
    {:noreply, confirm_status(socket)}
  end

  def handle_event("cancel-status", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_status, nil)
     |> assign(:comment, "")}
  end

  defp confirm_status(socket) do
    %{
      assigns: %{
        current_user: current_user,
        opinion: opinion,
        selected_status: status,
        comment: comment
      }
    } =
      socket

    comment = if comment == "", do: badge_label(status), else: comment

    attrs = %{
      opinion_id: opinion.id,
      user_id: current_user.id,
      status: status,
      comment: comment,
      model: "human"
    }

    case Verifications.create_verification(attrs) do
      {:ok, _verification} ->
        cached_status = if status == :unverified, do: nil, else: status
        updated_opinion = %{opinion | verification_status: cached_status}
        send(self(), {:verification_saved, opinion.id})

        socket
        |> assign(:opinion, updated_opinion)
        |> close_dropdown()

      {:error, :only_author_can_endorse} ->
        send(self(), {:put_flash, :error, "Only the opinion author can endorse."})
        close_dropdown(socket)

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to update verification status."})
        close_dropdown(socket)
    end
  end

  defp close_dropdown(socket) do
    socket
    |> assign(:show_dropdown, false)
    |> assign(:selected_status, nil)
    |> assign(:comment, "")
  end

  defp statuses_for(opinion, current_user) do
    base = @statuses

    if opinion.author_id && current_user.author_id &&
         opinion.author_id == current_user.author_id do
      [:endorsed | base]
    else
      base
    end
  end

  defp badge_classes(nil), do: "bg-gray-100 text-gray-800"
  defp badge_classes(:verified), do: "bg-green-100 text-green-800"
  defp badge_classes(:ai_verified), do: "bg-purple-100 text-purple-800"
  defp badge_classes(:endorsed), do: "bg-blue-100 text-blue-800"
  defp badge_classes(:disputed), do: "bg-orange-100 text-orange-800"
  defp badge_classes(:unverifiable), do: "bg-gray-200 text-gray-600"

  defp badge_label(nil), do: "Unverified"
  defp badge_label(:verified), do: "Verified"
  defp badge_label(:ai_verified), do: "AI Verified"
  defp badge_label(:endorsed), do: "Endorsed"
  defp badge_label(:disputed), do: "Disputed"
  defp badge_label(:unverifiable), do: "Unverifiable"
  defp badge_label(:unverified), do: "Unverified"

  defp badge_text_class(:verified), do: "text-green-700"
  defp badge_text_class(:ai_verified), do: "text-purple-700"
  defp badge_text_class(:endorsed), do: "text-blue-700"
  defp badge_text_class(:disputed), do: "text-orange-700"
  defp badge_text_class(:unverifiable), do: "text-gray-600"
  defp badge_text_class(:unverified), do: "text-gray-500"
end
