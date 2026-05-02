defmodule YouCongressWeb.Components.VerificationHistory do
  @moduledoc """
  Shared component for rendering verification history entries.
  """

  use Phoenix.Component
  use YouCongressWeb, :verified_routes

  import YouCongressWeb.Tools.TimeAgo, only: [short_time: 1]

  attr :verifications, :list, required: true
  attr :wrapper_class, :string, default: ""
  attr :title, :string, default: "Verification History"
  attr :title_tag, :string, default: "h3"
  attr :title_class, :string, default: "text-xs font-semibold mb-2 text-gray-500"
  attr :entries_class, :string, default: "space-y-1"

  def verification_history(assigns) do
    ~H"""
    <div class={@wrapper_class}>
      <.dynamic_tag tag_name={@title_tag} class={@title_class}>{@title}</.dynamic_tag>
      <div class={@entries_class}>
        <%= for verification <- @verifications do %>
          <div class="flex items-center gap-2 text-xs text-gray-500">
            <span class={[
              "inline-flex items-center rounded px-2 py-0.5 font-medium whitespace-nowrap",
              status_badge_classes(verification.status)
            ]}>
              {status_label(verification.status)}
            </span>
            <span>{verification.comment}</span>
            <span>&middot;</span>
            <%= if verification.user && verification.user.author do %>
              <a
                href={~p"/a/#{verification.user.author.id}"}
                class="text-indigo-600 hover:underline"
              >
                {verification.user.author.name}
              </a>
            <% else %>
              <span>Unknown</span>
            <% end %>
            <%= if verification.model && verification.model != "human" do %>
              <span
                class="inline-flex items-center gap-1 text-purple-600"
                title={"AI model: #{verification.model}"}
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-3 w-3"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                >
                  <path d="M13 7H7v6h6V7z" />
                  <path
                    fill-rule="evenodd"
                    d="M7 2a1 1 0 012 0v1h2V2a1 1 0 112 0v1h1a2 2 0 012 2v1h1a1 1 0 110 2h-1v2h1a1 1 0 110 2h-1v1a2 2 0 01-2 2h-1v1a1 1 0 11-2 0v-1H9v1a1 1 0 11-2 0v-1H6a2 2 0 01-2-2v-1H3a1 1 0 110-2h1V9H3a1 1 0 010-2h1V6a2 2 0 012-2h1V2zm1 3H6v10h8V5H8z"
                    clip-rule="evenodd"
                  />
                </svg>
                {verification.model}
              </span>
            <% end %>
            <span class="inline-flex items-center gap-1 whitespace-nowrap">
              &middot; {short_time(verification.updated_at)}
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_badge_classes(:verified), do: "bg-green-100 text-green-800"
  defp status_badge_classes(:ai_verified), do: "bg-gray-100 text-gray-600"
  defp status_badge_classes(:ai_unverifiable), do: "bg-gray-100 text-gray-600"
  defp status_badge_classes(:endorsed), do: "bg-blue-100 text-blue-800"
  defp status_badge_classes(:disputed), do: "bg-orange-100 text-orange-800"
  defp status_badge_classes(:unverifiable), do: "bg-gray-200 text-gray-600"
  defp status_badge_classes(:unverified), do: "bg-gray-100 text-gray-800"

  defp status_label(:verified), do: "Verified"
  defp status_label(:ai_verified), do: "AI Verified"
  defp status_label(:ai_unverifiable), do: "AI Unverifiable"
  defp status_label(:endorsed), do: "Endorsed"
  defp status_label(:disputed), do: "Disputed"
  defp status_label(:unverifiable), do: "Unverifiable"
  defp status_label(:unverified), do: "Unverified"
end
