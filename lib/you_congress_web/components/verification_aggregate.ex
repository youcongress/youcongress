defmodule YouCongressWeb.Components.VerificationAggregate do
  @moduledoc """
  Aggregate verification badge for a quote shown in a statement context.

  It combines the three progressive verification dimensions — quote authenticity,
  opinion-statement relevance, and the vote's answer — into a single badge that
  only reads "Verified" when all three are positive (see
  `YouCongress.VerificationStatus.aggregate/3`).

  For users who can verify, clicking the badge opens a popover with one row per
  dimension. Downstream rows are disabled until the upstream dimension is
  positive, mirroring the server-side progressive gate.

  Expects assigns: `opinion`, `opinion_statement` (may be nil), `vote` (may be
  nil), `current_user`.
  """

  use YouCongressWeb, :live_component

  alias YouCongress.Accounts.Permissions
  alias YouCongress.VerificationStatus
  alias YouCongress.Verifications
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.VoteVerifications

  @row_statuses ~w(verified disputed unverifiable unverified)a

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:opinion, assigns.opinion)
      |> assign(:opinion_statement, assigns[:opinion_statement])
      |> assign(:vote, assigns[:vote])
      |> assign(:current_user, assigns[:current_user])
      |> assign(:class, assigns[:class] || "ml-2")

    # Honor an explicitly passed open state (e.g. tests); otherwise preserve the
    # current state across parent re-renders.
    socket =
      case assigns do
        %{show_dropdown: show} -> assign(socket, :show_dropdown, show)
        _ -> assign_new(socket, :show_dropdown, fn -> false end)
      end

    {:ok, socket}
  end

  def render(assigns) do
    assigns =
      assign(assigns, :aggregate, aggregate_status(assigns))

    ~H"""
    <span class={[@class, "relative inline-block"]}>
      <%= if @current_user && Permissions.can_verify_opinion?(@current_user) do %>
        <span
          class={[
            "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium cursor-pointer",
            badge_classes(@aggregate)
          ]}
          phx-click="toggle-dropdown"
          phx-target={@myself}
        >
          {badge_label(@aggregate)}
        </span>
        <%= if @show_dropdown do %>
          <div class="absolute z-10 bottom-full mb-1 left-0 w-max max-w-[90vw] bg-white border rounded shadow-lg p-2 space-y-2">
            {render_row(assign(assigns, :row, :quote))}
            {render_row(assign(assigns, :row, :relevance))}
            {render_row(assign(assigns, :row, :vote))}
          </div>
        <% end %>
      <% else %>
        <Phoenix.Component.link
          href="/faq#verify-quotes"
          class={[
            "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium",
            badge_classes(@aggregate)
          ]}
        >
          {badge_label(@aggregate)}
        </Phoenix.Component.link>
      <% end %>
    </span>
    """
  end

  defp render_row(assigns) do
    assigns =
      assigns
      |> assign(:row_label, row_label(assigns.row))
      |> assign(:status, row_status(assigns, assigns.row))
      |> assign(:row_state, row_state(assigns, assigns.row))

    ~H"""
    <div class="flex items-center gap-1 flex-wrap">
      <span class="text-xs text-gray-500 w-16 shrink-0">{@row_label}</span>
      <span class={[
        "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium",
        badge_classes(@status)
      ]}>
        {badge_label(@status)}
      </span>
      <%= case @row_state do %>
        <% :enabled -> %>
          <%= for status <- row_options(@row, assigns) do %>
            <button
              phx-click="verify"
              phx-value-subject={@row}
              phx-value-status={status}
              phx-target={@myself}
              class={["text-xs px-1.5 py-0.5 rounded hover:bg-gray-100", badge_text_class(status)]}
              title={badge_label(status)}
            >
              {short_label(status)}
            </button>
          <% end %>
        <% {:disabled, hint} -> %>
          <span class="text-xs text-gray-400 italic">{hint}</span>
      <% end %>
    </div>
    """
  end

  def handle_event("toggle-dropdown", _, socket) do
    {:noreply, assign(socket, :show_dropdown, !socket.assigns.show_dropdown)}
  end

  def handle_event("verify", %{"subject" => subject, "status" => status}, socket) do
    status = String.to_existing_atom(status)
    {:noreply, verify(socket, subject, status)}
  end

  defp verify(socket, "quote", status) do
    %{opinion: opinion, current_user: user} = socket.assigns

    case Verifications.create_verification(%{
           opinion_id: opinion.id,
           user_id: user.id,
           status: status,
           comment: badge_label(status),
           model: "human"
         }) do
      {:ok, _} ->
        opinion = %{opinion | verification_status: cache(status)}
        notify_saved(:opinion, opinion.id)
        assign(socket, :opinion, opinion)

      {:error, reason} ->
        flash_error(reason)
        socket
    end
  end

  defp verify(socket, "relevance", status) do
    %{opinion_statement: os, current_user: user} = socket.assigns

    case OpinionStatementVerifications.create_verification(%{
           opinion_statement_id: os.id,
           user_id: user.id,
           status: status,
           comment: badge_label(status),
           model: "human"
         }) do
      {:ok, _} ->
        os = %{os | verification_status: cache(status)}
        notify_saved(:opinion_statement, os.id)
        assign(socket, :opinion_statement, os)

      {:error, reason} ->
        flash_error(reason)
        socket
    end
  end

  defp verify(socket, "vote", status) do
    %{vote: vote, current_user: user} = socket.assigns

    case VoteVerifications.create_verification(%{
           vote_id: vote.id,
           user_id: user.id,
           status: status,
           comment: badge_label(status),
           model: "human"
         }) do
      {:ok, _} ->
        vote = %{vote | verification_status: cache(status)}
        notify_saved(:vote, vote.id)
        assign(socket, :vote, vote)

      {:error, reason} ->
        flash_error(reason)
        socket
    end
  end

  defp cache(:unverified), do: nil
  defp cache(status), do: status

  defp notify_saved(subject_type, id) do
    send(self(), {:verification_saved, subject_type, id})
  end

  defp flash_error(:only_author_can_endorse),
    do: send(self(), {:put_flash, :error, "Only the opinion author can endorse."})

  defp flash_error(:quote_not_verified),
    do: send(self(), {:put_flash, :error, "Verify the quote before its relevance or vote."})

  defp flash_error(:relevance_not_verified),
    do: send(self(), {:put_flash, :error, "Verify the relevance before the vote."})

  defp flash_error(_),
    do: send(self(), {:put_flash, :error, "Failed to update verification status."})

  # --- aggregate + row state -------------------------------------------------

  defp aggregate_status(assigns) do
    VerificationStatus.aggregate(
      authenticity_status(assigns),
      relevance_status(assigns),
      vote_status(assigns)
    )
  end

  defp authenticity_status(%{opinion: opinion}), do: opinion.verification_status

  defp relevance_status(%{opinion_statement: %{verification_status: status}}), do: status
  defp relevance_status(_), do: nil

  # The answer's correctness is a property of the vote itself, independent of
  # which of the author's quotes is currently shown — so any present vote counts.
  defp vote_status(%{vote: %{verification_status: status}}), do: status
  defp vote_status(_), do: nil

  defp row_status(assigns, :quote), do: authenticity_status(assigns)
  defp row_status(assigns, :relevance), do: relevance_status(assigns)
  defp row_status(assigns, :vote), do: vote_status(assigns)

  # Returns :enabled or {:disabled, hint} explaining exactly what blocks the row.
  defp row_state(_assigns, :quote), do: :enabled

  defp row_state(assigns, :relevance) do
    cond do
      is_nil(assigns.opinion_statement) ->
        {:disabled, "not linked to statement"}

      not VerificationStatus.positive?(authenticity_status(assigns)) ->
        {:disabled, "verify quote first"}

      true ->
        :enabled
    end
  end

  defp row_state(assigns, :vote) do
    cond do
      is_nil(assigns.vote) ->
        {:disabled, "no vote"}

      not VerificationStatus.positive?(authenticity_status(assigns)) ->
        {:disabled, "verify quote first"}

      not VerificationStatus.positive?(relevance_status(assigns)) ->
        {:disabled, "verify relevance first"}

      true ->
        :enabled
    end
  end

  # The author may endorse their own quote (authenticity row only).
  defp row_options(:quote, %{opinion: opinion, current_user: %{author_id: author_id}})
       when not is_nil(author_id) do
    if opinion.author_id == author_id, do: [:endorsed | @row_statuses], else: @row_statuses
  end

  defp row_options(_row, _assigns), do: @row_statuses

  defp row_label(:quote), do: "Quote"
  defp row_label(:relevance), do: "Relevance"
  defp row_label(:vote), do: "Vote"

  # --- labels & colors -------------------------------------------------------

  defp short_label(:verified), do: "Verify"
  defp short_label(:endorsed), do: "Endorse"
  defp short_label(:disputed), do: "Dispute"
  defp short_label(:unverifiable), do: "Unverifiable"
  defp short_label(:unverified), do: "Clear"
  defp short_label(status), do: badge_label(status)

  defp badge_classes(:verified), do: "bg-green-100 text-green-800"
  defp badge_classes(:ai_verified), do: "bg-gray-100 text-gray-600"
  defp badge_classes(:ai_unverifiable), do: "bg-gray-100 text-gray-600"
  defp badge_classes(:endorsed), do: "bg-blue-100 text-blue-800"
  defp badge_classes(:disputed), do: "bg-orange-100 text-orange-800"
  defp badge_classes(:unverifiable), do: "bg-gray-200 text-gray-600"
  defp badge_classes(_), do: "bg-gray-100 text-gray-800"

  defp badge_label(:verified), do: "Verified"
  defp badge_label(:ai_verified), do: "AI Verified"
  defp badge_label(:ai_unverifiable), do: "AI Unverifiable"
  defp badge_label(:endorsed), do: "Endorsed"
  defp badge_label(:disputed), do: "Disputed"
  defp badge_label(:unverifiable), do: "Unverifiable"
  defp badge_label(:unverified), do: "Unverified"
  defp badge_label(nil), do: "Unverified"

  defp badge_text_class(:verified), do: "text-green-700"
  defp badge_text_class(:endorsed), do: "text-blue-700"
  defp badge_text_class(:disputed), do: "text-orange-700"
  defp badge_text_class(:unverifiable), do: "text-gray-600"
  defp badge_text_class(:unverified), do: "text-gray-500"
  defp badge_text_class(_), do: "text-gray-600"
end
