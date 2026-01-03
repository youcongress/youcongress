defmodule YouCongressWeb.StatementLive.AddQuote do
  require Logger

  use YouCongressWeb, :live_view

  alias Phoenix.LiveView.Socket
  alias YouCongress.Statements
  alias YouCongress.Authors

  alias YouCongress.Votes
  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
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
    statement = Statements.get_by!(slug: slug)

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
           statement: statement,
           form: form,
           agree_rate_options: ["For", "Against", "Abstain"],
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
            statement: statement,
            form: form,
            agree_rate_options: ["For", "Against", "Abstain"],
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
       to: ~p"/p/#{socket.assigns.statement.slug}/add-quote"
     )}
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
          original_wikipedia_url = wikipedia_url

          en_wikipedia_url =
            String.replace(original_wikipedia_url, ~r/https?:\/\/\w+\./, "https://en.")

          Authors.get_author_by(wikipedia_url: en_wikipedia_url) ||
            Authors.get_author_by(wikipedia_url: original_wikipedia_url)

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
        statement = socket.assigns.statement

        url = add_quote_url(statement, author)

        socket =
          socket
          |> push_patch(to: url)
          |> assign(:author, author)
          |> assign(:wikipedia_url, author.wikipedia_url)

        {:noreply, socket}
    end
  end

  def handle_event("add-author", params, socket) do
    twitter_username =
      case params["twitter_username"] do
        "@" <> username -> username
        "https://x.com/" <> username -> username
        "https://twitter.com/" <> username -> username
        username -> username
      end

    args = %{
      twitter_username: twitter_username,
      name: params["name"],
      bio: params["bio"],
      wikipedia_url: params["wikipedia_url"],
      user_id: socket.assigns.current_user.id,
      twin_origin: false
    }

    case Authors.create_author(args) do
      {:ok, author} ->
        statement = socket.assigns.statement

        url = add_quote_url(statement, author)

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
    %{assigns: %{statement: statement, author: author}} = socket
    answer = String.downcase(response || "") |> String.to_existing_atom()

    case Votes.get_by(statement_id: statement.id, author_id: author.id) do
      nil ->
        create_vote_and_opinion(statement, author, answer, opinion, source_url, socket)

      vote ->
        create_opinion_and_update_vote(vote, author, answer, opinion, source_url, socket)
    end
  end

  defp create_vote_and_opinion(statement, author, answer, opinion, source_url, socket) do
    %{assigns: %{current_user: current_user}} = socket

    with {:ok, %{opinion: opinion}} <-
           Opinions.create_opinion(%{
             content: opinion,
             author_id: author.id,
             source_url: source_url,
             user_id: current_user.id,
             verified_at: nil,
             direct: true,
             twin: false
           }),
         {:ok, _opinion_statement} <-
           OpinionsStatements.create_opinion_statement(%{
             opinion_id: opinion.id,
             statement_id: statement.id,
             user_id: current_user.id
           }),
         {:ok, _vote} <-
           Votes.create_vote(%{
             statement_id: statement.id,
             author_id: author.id,
             answer: answer,
             opinion_id: opinion.id
           }) do
      Track.event("Add Quote", current_user)

      url = add_quote_url(statement, author)

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

  defp create_opinion_and_update_vote(vote, author, answer, opinion, source_url, socket) do
    %{assigns: %{current_user: current_user, statement: statement}} = socket

    with {:ok, %{opinion: opinion}} <-
           Opinions.create_opinion(%{
             content: opinion,
             author_id: author.id,
             source_url: source_url,
             user_id: current_user.id,
             verified_at: nil,
             direct: true,
             twin: false
           }),
         {:ok, _opinion_statement} <-
           OpinionsStatements.create_opinion_statement(%{
             opinion_id: opinion.id,
             statement_id: statement.id,
             user_id: current_user.id
           }),
         {:ok, _vote} <-
           Votes.update_vote(vote, %{
             opinion_id: opinion.id,
             answer: answer,
             twin: false
           }) do
      Track.event("Add Quote", current_user)

      url = add_quote_url(statement, author)

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

  defp add_quote_url(statement, author) do
    cond do
      !is_nil(author.twitter_username) ->
        ~p"/p/#{statement.slug}/add-quote?twitter_username=#{author.twitter_username}"

      !is_nil(author.wikipedia_url) ->
        ~p"/p/#{statement.slug}/add-quote?wikipedia_url=#{author.wikipedia_url}"

      true ->
        ~p"/p/#{statement.slug}/add-quote?a=#{author.id}"
    end
  end
end
