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
    voting = Votings.get_by!(slug: slug)

    twitter_username = params["twitter_username"]
    wikipedia_url = params["wikipedia_url"]
    author_id = params["a"]

    author =
      cond do
        twitter_username -> Authors.get_author_by(twitter_username: twitter_username)
        wikipedia_url -> Authors.get_author_by(wikipedia_url: wikipedia_url)
        author_id -> Authors.get_author!(author_id)
        true -> nil
      end

    case author do
      nil ->
        form =
          to_form(%{
            "twitter_username" => nil,
            "wikipedia_url" => nil,
            "name" => nil,
            "bio" => nil,
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
           wikipedia_url: nil,
           name: nil,
           bio: nil
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
            twitter_username: author.twitter_username,
            wikipedia_url: author.wikipedia_url,
            name: nil,
            bio: nil
          )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove-author", _, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/p/#{socket.assigns.voting.slug}/add-quote"
     )}
  end

  def handle_event(
        "add-author",
        %{"twitter_username" => "@" <> twitter_username} = params,
        %{assigns: %{twitter_username: nil, wikipedia_url: nil}} = socket
      ) do
    params = Map.put(params, "twitter_username", twitter_username)
    handle_event("add-author", params, socket)
  end

  def handle_event(
        "add-author",
        params,
        %{assigns: %{twitter_username: nil, wikipedia_url: nil}} = socket
      ) do
    twitter_username = params["twitter_username"]
    wikipedia_url = params["wikipedia_url"]

    author =
      cond do
        twitter_username && twitter_username != "" ->
          Authors.get_author_by(twitter_username: twitter_username)

        wikipedia_url && wikipedia_url != "" ->
          Authors.get_author_by(wikipedia_url: wikipedia_url)

        true ->
          nil
      end

    case author do
      nil ->
        socket =
          assign(socket,
            twitter_username: twitter_username,
            wikipedia_url: wikipedia_url
          )

        {:noreply, put_flash(socket, :info, "Author not found. Please fill the form.")}

      author ->
        voting = socket.assigns.voting

        url = add_quote_url(voting, author)

        {:noreply, push_patch(socket, to: url)}
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

        url = add_quote_url(voting, author)

        socket =
          socket
          |> push_patch(to: url)
          |> assign(:author, author)
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

    case Votes.get_by(voting_id: voting.id, author_id: author.id) do
      nil ->
        create_vote_and_opinion(voting, author, answer_id, opinion, source_url, socket)

      vote ->
        create_opinion_and_update_vote(vote, author, answer_id, opinion, source_url, socket)
    end
  end

  defp create_vote_and_opinion(voting, author, answer_id, opinion, source_url, socket) do
    %{assigns: %{current_user: current_user}} = socket

    with {:ok, opinion} <-
           Opinions.create_opinion(%{
             content: opinion,
             author_id: author.id,
             source_url: source_url,
             user_id: current_user.id,
             direct: true,
             twin: false,
             voting_id: voting.id
           }),
         {:ok, _vote} <-
           Votes.create_vote(%{
             voting_id: voting.id,
             author_id: author.id,
             answer_id: answer_id,
             opinion_id: opinion.id
           }) do
      Track.event("Add Quote", current_user)

      url = add_quote_url(voting, author)

      socket =
        socket
        |> put_flash(:info, "Quote added.")
        |> redirect(to: url)

      {:noreply, socket}
    else
      {:error, changeset} ->
        error_message =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} ->
            msg
          end)

        {:noreply,
         socket
         |> put_flash(:error, "Error. Please try again")
         |> assign(:errors, error_message)}
    end
  end

  defp create_opinion_and_update_vote(vote, author, answer_id, opinion, source_url, socket) do
    %{assigns: %{current_user: current_user, voting: voting}} = socket

    with {:ok, opinion} <-
           Opinions.create_opinion(%{
             content: opinion,
             author_id: author.id,
             source_url: source_url,
             user_id: current_user.id,
             direct: true,
             twin: false,
             voting_id: vote.voting_id
           }),
         {:ok, _vote} <-
           Votes.update_vote(vote, %{
             opinion_id: opinion.id,
             answer_id: answer_id,
             twin: false
           }) do
      Track.event("Add Quote", current_user)

      url = add_quote_url(voting, author)

      socket =
        socket
        |> put_flash(:info, "Quote added.")
        |> redirect(to: url)

      {:noreply, socket}
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

  defp add_quote_url(voting, author) do
    cond do
      !is_nil(author.twitter_username) ->
        ~p"/p/#{voting.slug}/add-quote?twitter_username=#{author.twitter_username}"

      !is_nil(author.wikipedia_url) ->
        ~p"/p/#{voting.slug}/add-quote?wikipedia_url=#{author.wikipedia_url}"

      true ->
        ~p"/p/#{voting.slug}/add-quote?a=#{author.id}"
    end
  end
end
