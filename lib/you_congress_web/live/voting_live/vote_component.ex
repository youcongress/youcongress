defmodule YouCongressWeb.VotingLive.VoteComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Delegations
  alias YouCongress.Likes
  alias YouCongressWeb.Tools.Tooltip
  alias YouCongressWeb.VotingLive.VoteComponent.AiQuoteMenu
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongressWeb.Tools.TimeAgo
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Opinions

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to like."})
    {:noreply, socket}
  end

  def handle_event("like", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, vote: vote}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.like(opinion_id, current_user) do
      {:ok, _} ->
        opinion = Map.put(vote.opinion, :likes_count, vote.opinion.likes_count + 1)
        vote = Map.put(vote, :opinion, opinion)

        socket =
          socket
          |> assign(:liked, true)
          |> assign(:vote, vote)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error liking opinion.")}
    end
  end

  def handle_event("unlike", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, vote: vote}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.unlike(opinion_id, current_user) do
      {:ok, _} ->
        opinion = Map.put(vote.opinion, :likes_count, vote.opinion.likes_count - 1)
        vote = Map.put(vote, :opinion, opinion)

        socket =
          socket
          |> assign(:liked, false)
          |> assign(:vote, vote)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error unliking opinion.")}
    end
  end

  def handle_event("verify-opinion", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to verify quotes."})
    {:noreply, socket}
  end

  def handle_event("verify-opinion", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, vote: vote}} = socket
    opinion_id = String.to_integer(opinion_id)

    if Permissions.can_verify_opinion?(current_user) do
      opinion = vote.opinion

      if opinion.id == opinion_id do
        verifier_id = current_user && current_user.id

        case Opinions.update_opinion(opinion, %{is_verified: true, verified_by_user_id: verifier_id}) do
          {:ok, updated_opinion} ->
            updated_vote = Map.put(vote, :opinion, updated_opinion)
            {:noreply, assign(socket, :vote, updated_vote)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to verify quote.")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to verify.")}
    end
  end

  def handle_event("unverify-opinion", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to verify quotes."})
    {:noreply, socket}
  end

  def handle_event("unverify-opinion", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, vote: vote}} = socket
    opinion_id = String.to_integer(opinion_id)

    if Permissions.can_verify_opinion?(current_user) do
      opinion = vote.opinion

      if opinion.id == opinion_id do
        case Opinions.update_opinion(opinion, %{is_verified: false, verified_by_user_id: nil}) do
          {:ok, updated_opinion} ->
            updated_vote = Map.put(vote, :opinion, updated_opinion)
            {:noreply, assign(socket, :vote, updated_vote)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to unverify quote.")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to verify.")}
    end
  end

  def handle_event("add-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    send(
      self(),
      {:put_flash, :warning, "Log in to unlock delegate voting."}
    )

    {:noreply, socket}
  end

  def handle_event("add-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket
    delegate_id = String.to_integer(author_id)

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        send(
          self(),
          {:put_flash, :info,
           "Added to your delegation list. You're voting as the majority of your delegates – unless you directly vote."}
        )

        socket =
          socket
          |> assign(:delegating?, true)
          |> assign(:reload, true)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
  end

  def handle_event("remove-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to remove your delegates."})
    socket = assign(socket, :delegating?, false)
    {:noreply, socket}
  end

  def handle_event("remove-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket
    delegate_id = String.to_integer(author_id)

    case Delegations.delete_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, false)
          |> assign(:reload, true)

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  defdelegate author_path(path), to: YouCongressWeb.AuthorLive.Show, as: :author_path

  defp response(assigns, response) do
    assigns =
      assign(assigns, color: response_color(response), response: String.downcase(response))

    ~H"""
    <span class={"#{@color} font-bold"}>
      <%= @response %>
    </span>
    """
  end

  def response_with_s(assigns, response) do
    assigns =
      assign(assigns, color: response_color(response), response: with_s(response))

    ~H"""
    <span class={"#{@color} font-bold"}>
      <%= @response %>
    </span>
    """
  end

  defp with_s("Agree"), do: "agrees"
  defp with_s("Strongly agree"), do: "strongly agrees"
  defp with_s("Disagree"), do: "disagrees"
  defp with_s("Strongly disagree"), do: "strongly disagrees"
  defp with_s("Abstain"), do: "abstains"
  defp with_s("N/A"), do: "N/A"

  defp response_color("Agree"), do: "text-lime-800"
  defp response_color("Strongly agree"), do: "text-green-800"
  defp response_color("Disagree"), do: "text-orange-800"
  defp response_color("Strongly disagree"), do: "text-red-800"
  defp response_color("Abstain"), do: "text-blue-800"
  defp response_color("N/A"), do: "text-gray-800"
end
