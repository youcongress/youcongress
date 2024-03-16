defmodule YouCongressWeb.VotingLive.Show.Comments do
  @moduledoc """
  Handle post events to create, update and delete a comment
  """

  require Logger

  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 2]
  import YouCongressWeb.VotingLive.Show.VotesLoader, only: [load_voting_and_votes: 2]

  alias YouCongress.Votes.Answers
  alias YouCongress.Votes

  def post_event(opinion, %{assigns: %{current_user_vote: nil}} = socket) do
    opinion = clean_opinion(opinion)

    if opinion do
      create_vote(opinion, socket)
    else
      {:noreply, put_flash(socket, :error, "Comment can't be blank.")}
    end
  end

  def post_event(opinion, socket) do
    # current_user_vote is not nil
    %{assigns: %{current_user_vote: current_user_vote, voting: voting}} = socket

    opinion = clean_opinion(opinion)
    no_answer_id = Answers.answer_id_by_response("N/A")

    cond do
      is_nil(opinion) && is_nil(current_user_vote.opinion) ->
        {:noreply, put_flash(socket, :error, "Comment can't be blank.")}

      opinion || current_user_vote.answer_id != no_answer_id ->
        update_vote(voting, current_user_vote, opinion, socket)

      true ->
        delete_vote(voting, current_user_vote, socket)
    end
  end

  defp create_vote(opinion, socket) do
    %{assigns: %{current_user: current_user, voting: voting}} = socket

    case Votes.create_vote(%{
           voting_id: voting.id,
           author_id: current_user.author_id,
           opinion: opinion,
           answer_id: Answers.answer_id_by_response("N/A")
         }) do
      {:ok, _} ->
        socket =
          socket
          |> assign(editing: false)
          |> load_voting_and_votes(voting.id)
          |> put_flash(:info, "Comment created successfully.")

        {:noreply, socket}

      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error. Please try again.")}
    end
  end

  defp update_vote(voting, current_user_vote, opinion, socket) do
    case Votes.update_vote(current_user_vote, %{opinion: opinion}) do
      {:ok, vote} ->
        verb = if opinion, do: "updated", else: "deleted"

        socket =
          socket
          |> load_voting_and_votes(voting.id)
          |> assign(current_user_vote: vote, editing: !opinion)
          |> put_flash(:info, "Your comment has been #{verb}.")

        {:noreply, socket}

      {:error, _vote} ->
        {:noreply, put_flash(socket, :error, "Error. Please try again.")}
    end
  end

  defp delete_vote(voting, current_user_vote, socket) do
    case Votes.delete_vote(current_user_vote) do
      {:ok, _} ->
        socket =
          socket
          |> load_voting_and_votes(voting.id)
          |> assign(editing: true)
          |> put_flash(:info, "Your comment has been deleted.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error. Please try again.")}
    end
  end

  def delete_event(socket) do
    %{assigns: %{current_user_vote: current_user_vote, voting: voting}} = socket
    no_answer_id = Answers.answer_id_by_response("N/A")

    if current_user_vote.answer_id == no_answer_id do
      delete_vote(voting, current_user_vote, socket)
    else
      case Votes.update_vote(current_user_vote, %{opinion: nil}) do
        {:ok, vote} ->
          socket =
            socket
            |> load_voting_and_votes(voting.id)
            |> assign(current_user_vote: vote)
            |> put_flash(:info, "Your comment has been deleted.")

          {:noreply, socket}

        {:error, _vote} ->
          {:noreply, put_flash(socket, :error, "Error. Please try again.")}
      end
    end
  end

  defp clean_opinion(opinion) do
    opinion
    |> String.trim()
    |> case do
      "" -> nil
      opinion -> opinion
    end
  end
end
