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
  alias YouCongress.Opinions

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

  defp create_vote(opinion_content, socket) do
    %{assigns: %{current_user: current_user, voting: voting}} = socket

    args = %{
      content: opinion_content,
      author_id: current_user.author_id,
      user_id: current_user.id,
      voting_id: voting.id,
      twin: false
    }

    with {:ok, opinion} <- Opinions.create_opinion(args),
         {:ok, _} <-
           Votes.create_vote(%{
             voting_id: voting.id,
             author_id: current_user.author_id,
             opinion_id: opinion.id,
             answer_id: Answers.answer_id_by_response("N/A")
           }) do
      socket =
        socket
        |> assign(editing: false)
        |> load_voting_and_votes(voting.id)
        |> put_flash(:info, "Comment created successfully.")

      {:noreply, socket}
    else
      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error. Please try again.")}
    end
  end

  defp update_vote(voting, current_user_vote, nil, socket) do
    case Opinions.delete_opinion(current_user_vote.opinion) do
      {:ok, _} ->
        current_user_vote =
          Votes.get_current_user_vote(voting.id, socket.assigns.current_user.author_id)

        socket =
          socket
          |> load_voting_and_votes(voting.id)
          |> assign(current_user_vote: current_user_vote, editing: false)
          |> put_flash(:info, "Your comment has been deleted.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error. Please try again.")}
    end
  end

  defp update_vote(voting, %{opinion_id: nil} = current_user_vote, opinion_content, socket) do
    args = %{
      content: opinion_content,
      author_id: current_user_vote.author_id,
      user_id: socket.assigns.current_user.id,
      vote_id: current_user_vote.id,
      twin: current_user_vote.twin
    }

    with {:ok, opinion} <- Opinions.create_opinion(args),
         {:ok, _} <- Votes.update_vote(current_user_vote, %{opinion_id: opinion.id}) do
      current_user_vote =
        Votes.get_current_user_vote(voting.id, socket.assigns.current_user.author_id)

      socket =
        socket
        |> load_voting_and_votes(voting.id)
        |> assign(current_user_vote: current_user_vote, editing: false)
        |> put_flash(:info, "Your comment has been updated.")

      {:noreply, socket}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error. Please try again.")}
    end
  end

  defp update_vote(voting, current_user_vote, opinion, socket) do
    case Opinions.update_opinion(current_user_vote.opinion, %{content: opinion}) do
      {:ok, opinion} ->
        current_user_vote =
          Votes.get_current_user_vote(voting.id, socket.assigns.current_user.author_id)

        socket =
          socket
          |> load_voting_and_votes(voting.id)
          |> assign(current_user_vote: current_user_vote, editing: !opinion)
          |> put_flash(:info, "Your comment has been updated.")

        {:noreply, socket}

      {:error, _} ->
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

    case Opinions.delete_opinion(current_user_vote.opinion) do
      {:ok, _opinion} ->
        current_user_vote =
          Votes.get_current_user_vote(voting.id, socket.assigns.current_user.author_id)

        socket =
          socket
          |> load_voting_and_votes(voting.id)
          |> assign(current_user_vote: current_user_vote)
          |> put_flash(:info, "Your comment has been deleted.")

        {:noreply, socket}

      {:error, _vote} ->
        {:noreply, put_flash(socket, :error, "Error. Please try again.")}
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
