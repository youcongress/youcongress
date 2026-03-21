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
    assigns =
      assigns
      |> assign(:pending_actions_json, pending_actions(assigns.votes))
      |> assign(:registration_component_id, registration_component_id(assigns.votes))

    ~H"""
    <.modal id={@id} show={@show} on_cancel={JS.push("close-vote-auth-modal")}>
      <div class="space-y-5">
        <div>
          <h2 class="text-xl font-semibold text-gray-900">Log in to vote</h2>
          <p :if={@pending_vote} class="text-sm text-gray-600 mt-1">
            You chose {humanize_answer(@pending_vote.answer)} on
            “{@pending_vote.statement_title}”.
          </p>
          <p :if={!@pending_vote} class="text-sm text-gray-600 mt-1">
            Log in with Google or sign up with email to save your vote.
          </p>
        </div>

        <LoginButtons.render
          message="Log in with Google:"
          pending_actions={@pending_actions_json}
        />

        <div class="border-t border-gray-200 pt-4">
          <h3 class="text-sm font-semibold text-gray-900 mb-3">
            Or sign up with email and password
          </h3>
          {live_render(@socket, YouCongressWeb.UserRegistrationLive,
            id: @registration_component_id,
            session: %{
              "delegate_ids" => [],
              "votes" => @votes,
              "embedded" => true
            }
          )}
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

  defp humanize_answer(answer) when is_atom(answer) do
    answer
    |> to_string()
    |> humanize_answer()
  end

  defp humanize_answer(answer) when is_binary(answer) do
    answer
    |> String.trim()
    |> String.downcase()
    |> case do
      "for" -> "For"
      "against" -> "Against"
      "abstain" -> "Abstain"
      other -> String.capitalize(other)
    end
  end

  defp humanize_answer(answer), do: to_string(answer)
end
