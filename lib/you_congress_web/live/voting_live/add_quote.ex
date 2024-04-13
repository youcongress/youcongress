defmodule YouCongressWeb.VotingLive.AddQuote do
  require Logger

  use YouCongressWeb, :live_view

  alias Phoenix.LiveView.Socket
  alias YouCongress.Votings
  alias YouCongress.Authors
  alias YouCongress.Votes.Answers
  alias YouCongress.Votes
  alias YouCongress.Opinions

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    %{assigns: %{current_user: current_user}} = socket

    if connected?(socket) do
      YouCongress.Track.event("View Add Quote", current_user)
    end

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug, "twitter_username" => twitter_username}, _, socket) do
    voting = Votings.get_voting_by_slug!(slug)

    case Authors.get_author_by_twitter_username(twitter_username) do
      nil ->
        {:noreply,
         assign(socket,
           twitter_username: twitter_username,
           voting: voting,
           author: nil,
           errors: nil
         )}

      author ->
        socket = assign(socket, author: author, twitter_username: twitter_username)

        form =
          to_form(%{
            # twitter_username: author.twitter_username,
            # name: author.name,
            # bio: author.bio,
            # wikipedia_url: author.wikipedia_url,
            agree_rate: nil,
            opinion: nil,
            source_url: nil
          })

        socket =
          socket
          |> assign(:page_title, "Add quote")
          |> assign(
            voting: voting,
            form: form,
            agree_rate_options: Answers.basic_responses(),
            errors: nil
          )

        {:noreply, socket}
    end
  end

  def handle_params(%{"slug" => slug}, _, socket) do
    voting = Votings.get_voting_by_slug!(slug)

    socket =
      socket
      |> assign(:page_title, "Add quote")
      |> assign(voting: voting, twitter_username: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "add-quote",
        %{"agree_rate" => response, "opinion" => opinion, "source_url" => source_url},
        socket
      ) do
    %{assigns: %{voting: voting, author: author}} = socket
    answer_id = Answers.get_answer_id(response)

    case Votes.get_vote(%{voting_id: voting.id, author_id: author.id}) do
      nil ->
        create_vote_and_opinion(voting, author, answer_id, opinion, source_url, socket)

      vote ->
        create_opinion_and_update_vote(vote, author, answer_id, opinion, source_url, socket)
    end
  end

  defp create_vote_and_opinion(voting, author, answer_id, opinion, source_url, socket) do
    %{assigns: %{current_user: current_user}} = socket

    with {:ok, vote} <-
           Votes.create_vote(%{
             voting_id: voting.id,
             author_id: author.id,
             answer_id: answer_id
           }),
         {:ok, opinion} <-
           Opinions.create_opinion(%{
             vote_id: vote.id,
             content: opinion,
             author_id: author.id,
             source_url: source_url,
             user_id: current_user.id,
             direct: true,
             twin: false
           }),
         {:ok, _vote} <- Votes.update_vote(vote, %{opinion_id: opinion.id}) do
      {:noreply, put_flash(socket, :info, "Quote added")}
    else
      {:error, changeset} ->
        error_message =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} ->
            msg
          end)

        {:noreply,
         socket |> put_flash(:error, "Error. Please try again") |> assign(:errors, error_message)}
    end
  end

  defp create_opinion_and_update_vote(vote, author, answer_id, opinion, source_url, socket) do
    %{assigns: %{current_user: current_user}} = socket

    with {:ok, opinion} <-
           Opinions.create_opinion(%{
             vote_id: vote.id,
             content: opinion,
             author_id: author.id,
             source_url: source_url,
             user_id: current_user.id,
             direct: true,
             twin: false
           }),
         {:ok, _vote} <-
           Votes.update_vote(vote, %{
             opinion_id: opinion.id,
             answer_id: answer_id,
             twin: false
           }) do
      {:noreply, put_flash(socket, :info, "Quote added.")}
    else
      {:error, changeset} ->
        error_message =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} ->
            msg
          end)

        {:noreply,
         socket |> put_flash(:error, "Error. Please try again") |> assign(:errors, error_message)}
    end
  end
end
