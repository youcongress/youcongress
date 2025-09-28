defmodule YouCongressWeb.Components.VerificationBadge do
  @moduledoc """
  A reusable LiveComponent for displaying and managing opinion verification status.

  For admins, it renders clickable badges that handle verification/unverification events internally.
  For non-admin users, it renders a static link to the FAQ.
  """

  use YouCongressWeb, :live_component

  alias YouCongress.Accounts.Permissions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Opinions

  @doc """
  Renders a verification badge for an opinion.

  ## Examples

       <.live_component
         module={YouCongressWeb.Components.VerificationBadge}
         id={opinion.id}
         opinion={opinion}
         current_user={current_user}
       />
  """

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:opinion, assigns.opinion)
     |> assign(:current_user, assigns[:current_user])
     |> assign(:class, assigns[:class] || "ml-2")}
  end

  def render(assigns) do
    ~H"""
    <span class={@class}>
      <%= if @current_user && Permissions.can_verify_opinion?(@current_user) do %>
        <%= if Opinion.verified?(@opinion) do %>
          <span
            class="bg-green-100 text-green-800 inline-flex items-center rounded px-2 py-0.5 text-xs font-medium cursor-pointer"
            phx-click="unverify-opinion"
            phx-value-opinion_id={@opinion.id}
            phx-target={@myself}
          >
            Verified
          </span>
        <% else %>
          <span
            class="bg-yellow-100 text-yellow-800 inline-flex items-center rounded px-2 py-0.5 text-xs font-medium cursor-pointer"
            phx-click="verify-opinion"
            phx-value-opinion_id={@opinion.id}
            phx-target={@myself}
          >
            Unverified
          </span>
        <% end %>
      <% else %>
        <Phoenix.Component.link
          href="/faq#verify-quotes"
          class={[
            "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium",
            Opinion.verified?(@opinion) && "bg-green-100 text-green-800",
            !Opinion.verified?(@opinion) && "bg-yellow-100 text-yellow-800"
          ]}
        >
          {if Opinion.verified?(@opinion), do: "Verified", else: "Unverified"}
        </Phoenix.Component.link>
      <% end %>
    </span>
    """
  end

  def handle_event("verify-opinion", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to verify quotes."})
    {:noreply, socket}
  end

  def handle_event("verify-opinion", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket
    opinion_id = String.to_integer(opinion_id)

    if Permissions.can_verify_opinion?(current_user) do
      if opinion.id == opinion_id do
        verifier_id = current_user && current_user.id

        case Opinions.update_opinion(opinion, %{
               verified_at: DateTime.utc_now(),
               verified_by_user_id: verifier_id
             }) do
          {:ok, updated_opinion} ->
            {:noreply, assign(socket, :opinion, updated_opinion)}

          {:error, _changeset} ->
            send(self(), {:put_flash, :error, "Failed to verify quote."})
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    else
      send(self(), {:put_flash, :error, "You don't have permission to verify."})
      {:noreply, socket}
    end
  end

  def handle_event("unverify-opinion", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to verify quotes."})
    {:noreply, socket}
  end

  def handle_event("unverify-opinion", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket
    opinion_id = String.to_integer(opinion_id)

    if Permissions.can_verify_opinion?(current_user) do
      if opinion.id == opinion_id do
        case Opinions.update_opinion(opinion, %{
               verified_at: nil,
               verified_by_user_id: nil
             }) do
          {:ok, updated_opinion} ->
            {:noreply, assign(socket, :opinion, updated_opinion)}

          {:error, _changeset} ->
            send(self(), {:put_flash, :error, "Failed to unverify quote."})
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    else
      send(self(), {:put_flash, :error, "You don't have permission to verify."})
      {:noreply, socket}
    end
  end
end
