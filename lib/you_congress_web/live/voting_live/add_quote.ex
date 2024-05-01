defmodule YouCongressWeb.VotingLive.AddQuote do
  require Logger

  use YouCongressWeb, :live_view

  alias Phoenix.LiveView.Socket
  alias YouCongress.Votings
  alias YouCongress.Authors
  alias YouCongress.Votes.Answers
  alias YouCongress.Votes
  alias YouCongress.Opinions
  alias YouCongress.Track

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    %{assigns: %{current_user: current_user}} = socket

    if connected?(socket) do
      Track.event("View Add Quote", current_user)
    end

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug} = params, _, socket) do
    voting = Votings.get_voting_by_slug!(slug)

    twitter_username = params["twitter_username"]

    case Authors.get_author_by_twitter_username(twitter_username) do
      nil ->
        form =
          to_form(%{
            "twitter_username" => nil,
            "name" => nil,
            "bio" => nil,
            "wikipedia_url" => nil,
            "agree_rate" => nil,
            "opinion" => nil,
            "source_url" => nil
          })

        {:noreply,
         assign(socket,
           voting: voting,
           form: form,
           agree_rate_options: Answers.basic_responses(),
           errors: nil,
           author: nil,
           twitter_username: nil,
           name: nil,
           bio: nil,
           wikipedia_url: nil
         )}

      author ->
        form =
          to_form(%{
            "agree_rate" => nil,
            "opinion" => nil,
            "source_url" => nil
          })

        socket =
          socket
          |> assign(:page_title, "Add quote")
          |> assign(
            voting: voting,
            form: form,
            agree_rate_options: Answers.basic_responses(),
            errors: nil,
            author: author,
            twitter_username: twitter_username,
            name: nil,
            bio: nil,
            wikipedia_url: nil
          )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove-author", _, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/v/#{socket.assigns.voting.slug}/add-quote"
     )}
  end

  def handle_event(
        "add-author",
        %{"twitter_username" => "@" <> twitter_username} = params,
        %{assigns: %{twitter_username: nil}} = socket
      ) do
    params = Map.put(params, "twitter_username", twitter_username)
    handle_event("add-author", params, socket)
  end

  def handle_event("add-author", params, %{assigns: %{twitter_username: nil}} = socket) do
    twitter_username = params["twitter_username"]

    case Authors.get_author_by_twitter_username(twitter_username) do
      nil ->
        socket = assign(socket, twitter_username: twitter_username)
        {:noreply, put_flash(socket, :info, "Author not found. Please fill the form.")}

      author ->
        voting = socket.assigns.voting

        {:noreply,
         push_patch(socket,
           to: ~p"/v/#{voting.slug}/add-quote?twitter_username=#{author.twitter_username}"
         )}
    end
  end

  def handle_event("add-author", params, socket) do
    args = %{
      twitter_username: params["twitter_username"],
      name: params["name"],
      bio: params["bio"],
      wikipedia_url: params["wikipedia_url"],
      user_id: socket.assigns.current_user.id,
      twin_origin: false
    }

    case Authors.create_author(args) do
      {:ok, author} ->
        voting = socket.assigns.voting

        socket =
          socket
          |> push_patch(
            to: ~p"/v/#{voting.slug}/add-quote?twitter_username=#{author.twitter_username}"
          )
          |> put_flash(:info, "Author created.")

        {:noreply, socket}

      {:error, changeset} ->
        error_message =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} ->
            msg
          end)

        Logger.error("Error creating author: #{inspect(error_message)}")

        {:noreply,
         socket
         |> put_flash(:error, "Error. Please try again")
         |> assign(
           errors: error_message,
           twitter_username: params["twitter_username"],
           name: params["name"],
           bio: params["bio"],
           wikipedia_url: params["wikipedia_url"]
         )}
    end
  end

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
      Track.event("Add Quote", current_user)
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
      Track.event("Add Quote", current_user)
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
