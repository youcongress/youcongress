defmodule YouCongressWeb.Components.VoteAuthModal do
  @moduledoc """
  Modal shown to guests when they try to vote, prompting them to log in or sign up.
  """

  use Phoenix.Component
  use YouCongressWeb, :verified_routes

  import YouCongressWeb.CoreComponents

  alias Phoenix.LiveView.JS
  alias YouCongressWeb.Components.LoginButtons

  attr :socket, :any, required: true
  attr :show, :boolean, default: true
  attr :pending_vote, :map, default: nil
  attr :votes, :map, default: %{}
  attr :id, :string, default: "vote-auth-modal"

  def vote_auth_modal(assigns) do
    login_buttons_id = login_buttons_id(assigns.id)
    login_heading_id = login_heading_id(assigns.id)
    email_heading_wrapper_id = email_heading_wrapper_id(assigns.id)
    email_heading_id = email_heading_id(assigns.id)

    assigns =
      assigns
      |> assign(:pending_actions_json, pending_actions(assigns.votes))
      |> assign(:registration_component_id, registration_component_id(assigns.votes))
      |> assign(:login_buttons_id, login_buttons_id)
      |> assign(:login_heading_id, login_heading_id)
      |> assign(:email_heading_wrapper_id, email_heading_wrapper_id)
      |> assign(:email_heading_id, email_heading_id)
      |> assign(
        :hide_target_ids,
        hide_target_ids(
          login_buttons_id,
          login_heading_id,
          email_heading_wrapper_id,
          email_heading_id
        )
      )

    ~H"""
    <.modal id={@id} show={@show} on_cancel={JS.push("close-vote-auth-modal")}>
      <div class="space-y-5">
        <div id={@login_heading_id}>
          <h2 class="text-xl font-semibold text-gray-900">Log in to vote</h2>
        </div>

        <div id={@login_buttons_id}>
          <LoginButtons.render pending_actions={@pending_actions_json} />
        </div>

        <div class="pt-4">
          <div id={@email_heading_wrapper_id} class="border-t border-gray-200 pt-4">
            <h3 id={@email_heading_id} class="text-sm font-semibold text-gray-900 mb-3">
              Or sign up with email and password
            </h3>
          </div>
          <div class="pt-2">
            {live_render(@socket, YouCongressWeb.UserRegistrationLive,
              id: @registration_component_id,
              session: %{
                "delegate_ids" => [],
                "votes" => @votes,
                "embedded" => true,
                "hide_targets" => @hide_target_ids,
                "reload_on_login" => true
              }
            )}
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  defp pending_actions(votes) when map_size(votes) == 0, do: nil

  defp pending_actions(votes) do
    Jason.encode!(%{delegate_ids: [], votes: votes})
  end

  defp registration_component_id(votes) do
    hash = :erlang.phash2(votes)
    "vote-auth-registration-#{hash}"
  end

  defp login_buttons_id(modal_id) do
    "#{modal_id}-login-buttons"
  end

  defp login_heading_id(modal_id) do
    "#{modal_id}-heading"
  end

  defp email_heading_wrapper_id(modal_id) do
    "#{modal_id}-email-heading-wrapper"
  end

  defp email_heading_id(modal_id) do
    "#{modal_id}-email-heading"
  end

  defp hide_target_ids(
         login_buttons_id,
         login_heading_id,
         email_heading_wrapper_id,
         email_heading_id
       ) do
    [login_buttons_id, login_heading_id, email_heading_wrapper_id, email_heading_id]
  end
end
