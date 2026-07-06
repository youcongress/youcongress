defmodule YouCongressWeb.Components.VerificationBadge do
  @moduledoc """
  A reusable LiveComponent for displaying and managing a verification status.

  It works for three independently verifiable subjects:

    * `:opinion`: is the quote authentic?
    * `:opinion_statement`: is the quote exactly about this statement?
    * `:vote`: is the vote's answer correct for the statement?

  For logged-in users with permission, it renders a clickable badge with a
  dropdown to select a status. For everyone else, it renders a static link to
  the FAQ.

  Callers pass either the new `subject_type` + `subject` assigns, or the legacy
  `opinion` assign (treated as `subject_type: :opinion`).
  """

  use YouCongressWeb, :live_component

  alias YouCongress.Accounts.Permissions
  alias YouCongress.Verifications
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.VoteVerifications

  @statuses ~w(verified endorsed disputed unverifiable unverified)a

  def update(assigns, socket) do
    {subject_type, subject} = resolve_subject(assigns)

    {:ok,
     socket
     |> assign(:subject_type, subject_type)
     |> assign(:subject, subject)
     |> assign(:current_user, assigns[:current_user])
     |> assign(:class, assigns[:class] || "ml-2")
     |> assign(:link_to_opinion, assigns[:link_to_opinion] || false)
     |> assign(:opinion_id, assigns[:opinion_id] || opinion_id(subject_type, subject))
     |> assign_new(:show_dropdown, fn -> false end)
     |> assign_new(:selected_status, fn -> nil end)
     |> assign_new(:comment, fn -> "" end)}
  end

  defp resolve_subject(%{subject_type: subject_type, subject: subject}),
    do: {subject_type, subject}

  defp resolve_subject(%{opinion: opinion}), do: {:opinion, opinion}

  def render(assigns) do
    ~H"""
    <span class={[@class, "relative inline-block"]}>
      <%= if @link_to_opinion && @opinion_id do %>
        <.link
          href={~p"/c/#{@opinion_id}"}
          class={[
            "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium",
            badge_classes(@subject.verification_status)
          ]}
        >
          {badge_label(@subject.verification_status)}
        </.link>
      <% else %>
        <%= if @current_user && Permissions.can_verify_opinion?(@current_user) do %>
          <span
            class={[
              "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium cursor-pointer",
              badge_classes(@subject.verification_status)
            ]}
            phx-click="toggle-dropdown"
            phx-target={@myself}
          >
            {badge_label(@subject.verification_status)}
          </span>
          <%= if @show_dropdown do %>
            <div class="absolute z-10 bottom-full mb-1 bg-white border rounded shadow-lg left-0">
              <%= if @selected_status do %>
                <div class="p-2 w-56">
                  <div class={["text-xs font-medium mb-1", badge_text_class(@selected_status)]}>
                    {badge_label(@selected_status)}
                  </div>
                  <input
                    id={"verification-comment-#{@subject_type}-#{@subject.id}"}
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
                  <%= for status <- statuses_for(@subject_type, @subject, @current_user) do %>
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
              badge_classes(@subject.verification_status)
            ]}
          >
            {badge_label(@subject.verification_status)}
          </Phoenix.Component.link>
        <% end %>
      <% end %>
    </span>
    """
  end

  defp opinion_id(:opinion, %{id: id}), do: id
  defp opinion_id(_subject_type, %{opinion_id: opinion_id}), do: opinion_id
  defp opinion_id(_subject_type, _subject), do: nil

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
        subject_type: subject_type,
        subject: subject,
        opinion_id: opinion_id,
        selected_status: status,
        comment: comment
      }
    } = socket

    comment = if comment == "", do: badge_label(status), else: comment

    case create_verification(subject_type, subject, current_user, status, comment, opinion_id) do
      {:ok, _verification} ->
        cached_status = if status == :unverified, do: nil, else: status
        updated_subject = %{subject | verification_status: cached_status}
        send(self(), {:verification_saved, subject_type, subject.id})

        socket
        |> assign(:subject, updated_subject)
        |> close_dropdown()

      {:error, :only_author_can_endorse} ->
        send(self(), {:put_flash, :error, "Only the opinion author or a verifier can endorse."})
        close_dropdown(socket)

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to update verification status."})
        close_dropdown(socket)
    end
  end

  defp create_verification(:opinion, subject, current_user, status, comment, _opinion_id) do
    Verifications.create_verification(%{
      opinion_id: subject.id,
      user_id: current_user.id,
      status: status,
      comment: comment,
      model: "human"
    })
  end

  defp create_verification(
         :opinion_statement,
         subject,
         current_user,
         status,
         comment,
         _opinion_id
       ) do
    OpinionStatementVerifications.create_verification(%{
      opinion_statement_id: subject.id,
      user_id: current_user.id,
      status: status,
      comment: comment,
      model: "human"
    })
  end

  defp create_verification(:vote, subject, current_user, status, comment, opinion_id) do
    VoteVerifications.create_verification(%{
      vote_id: subject.id,
      opinion_id: opinion_id,
      user_id: current_user.id,
      status: status,
      comment: comment,
      model: "human"
    })
  end

  defp close_dropdown(socket) do
    socket
    |> assign(:show_dropdown, false)
    |> assign(:selected_status, nil)
    |> assign(:comment, "")
  end

  defp statuses_for(_subject_type, _subject, _current_user), do: @statuses

  defp badge_classes(nil), do: "bg-gray-100 text-gray-800"
  defp badge_classes(:verified), do: "bg-green-100 text-green-800"
  defp badge_classes(:ai_verified), do: "bg-gray-100 text-gray-600"
  defp badge_classes(:ai_unverifiable), do: "bg-gray-100 text-gray-600"
  defp badge_classes(:endorsed), do: "bg-blue-100 text-blue-800"
  defp badge_classes(:disputed), do: "bg-orange-100 text-orange-800"
  defp badge_classes(:unverifiable), do: "bg-gray-200 text-gray-600"

  defp badge_label(nil), do: "Unverified"
  defp badge_label(:verified), do: "Verified"
  defp badge_label(:ai_verified), do: "AI Verified"
  defp badge_label(:ai_unverifiable), do: "AI Unverifiable"
  defp badge_label(:endorsed), do: "Endorsed"
  defp badge_label(:disputed), do: "Disputed"
  defp badge_label(:unverifiable), do: "Unverifiable"
  defp badge_label(:unverified), do: "Unverified"

  defp badge_text_class(:verified), do: "text-green-700"
  defp badge_text_class(:ai_verified), do: "text-gray-600"
  defp badge_text_class(:ai_unverifiable), do: "text-gray-600"
  defp badge_text_class(:endorsed), do: "text-blue-700"
  defp badge_text_class(:disputed), do: "text-orange-700"
  defp badge_text_class(:unverifiable), do: "text-gray-600"
  defp badge_text_class(:unverified), do: "text-gray-500"
end
