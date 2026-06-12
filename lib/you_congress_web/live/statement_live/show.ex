defmodule YouCongressWeb.StatementLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Likes
  alias YouCongress.Statements
  alias YouCongressWeb.StatementLive.Show.VotesLoader
  alias YouCongressWeb.StatementLive.Show.CurrentUserVoteComponent
  alias YouCongressWeb.StatementLive.VoteComponent
  alias YouCongressWeb.StatementLive.Show.Comments
  alias YouCongress.Track
  alias YouCongress.Workers.QuotatorWorker
  alias YouCongress.Accounts.Permissions
  alias YouCongressWeb.StatementLive.CastVoteComponent
  alias YouCongressWeb.StatementLive.ResultsComponent
  alias YouCongress.HallsStatements
  alias YouCongress.Opinions.Quotes.QuotatorAI
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongressWeb.ReturnTo
  alias YouCongressWeb.SEO

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    %{assigns: %{current_user: current_user}} = socket

    if connected?(socket) do
      Track.event("View Statement", current_user)
    end

    {:ok,
     socket
     |> assign(:random_statements_from_main_hall, [])
     |> assign(:pending_guest_votes, %{})
     |> assign(:pending_vote_prompt, nil)
     |> assign(:vote_auth_return_to, nil)
     |> assign(:show_vote_auth_modal, false)
     |> assign(:show_country_results, false)
     |> assign(:country_vote_frequencies, nil)
     |> assign(:country_results_filters, VoteFrequencies.default_country_filters())}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug}, url, socket) do
    statement = Statements.get_by!(slug: slug)

    socket =
      socket
      |> assign(:return_to, ReturnTo.from_url(url))
      |> assign(:page_title, page_title(socket.assigns.live_action, statement.title))
      |> assign(:canonical_url, url(~p"/p/#{statement.slug}"))
      |> assign(:og_type, "article")
      |> assign(:statement, statement)
      |> assign(reload: false)
      |> assign(full_width: true)
      |> assign(:show_ai_quote_action, true)
      |> assign(:regenerating_opinion_id, nil)
      |> assign(:find_quotes_in_progress, QuotatorAI.check_polling_job_status(statement.id))
      |> assign(:source_filter, :quotes)
      |> assign(:answer_filter, nil)
      |> load_statement_and_likes(statement)
      |> assign_page_description()
      |> load_random_statements(statement.id)

    current_user_vote = socket.assigns.current_user_vote
    socket = assign(socket, editing: !current_user_vote || !current_user_vote.opinion_id)

    {:noreply, socket}
  end

  def handle_params(%{"slug" => slug}, "edit", socket) do
    statement = Statements.get_by!(slug: slug)
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, page_title(socket.assigns.live_action, statement.title))
      |> assign(
        :page_description,
        "Find agreement, understand disagreement."
      )
      |> assign(:statement, statement)
      |> assign(:current_user, current_user)
      |> assign(:show_ai_quote_action, true)

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}

  def handle_event("find-sourced-quotes", %{"statement_id" => statement_id}, socket) do
    statement_id = String.to_integer(statement_id)
    current_user = socket.assigns.current_user

    cond do
      is_nil(current_user) ->
        {:noreply, redirect(socket, to: ReturnTo.log_in_path(nil, socket.assigns[:return_to]))}

      not Permissions.can_generate_ai_votes?(current_user) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "AI quote search uses credits. Email hello@youcongress.org to purchase access."
         )}

      true ->
        %{statement_id: statement_id, user_id: current_user.id}
        |> QuotatorWorker.new()
        |> Oban.insert()

        Track.event("Find quotes", current_user)

        socket =
          socket
          |> assign(:find_quotes_in_progress, true)
          |> clear_flash()

        {:noreply, socket}
    end
  end

  def handle_event("post", %{"comment" => opinion}, socket) do
    Comments.post_event(opinion, socket)
  end

  def handle_event("cancel-edit", _, socket) do
    socket =
      socket
      |> assign(editing: false)
      |> clear_flash()

    {:noreply, socket}
  end

  def handle_event("delete-comment", _, socket) do
    Comments.delete_event(socket)
  end

  def handle_event("reload", _, socket) do
    statement = socket.assigns.statement

    socket =
      socket
      |> load_statement_and_likes(statement)
      |> assign(:find_quotes_in_progress, QuotatorAI.check_polling_job_status(statement.id))
      |> assign(reload: false)
      |> clear_flash()

    {:noreply, socket}
  end

  def handle_event("edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("filter-quotes", _, socket) do
    %{assigns: %{source_filter: source_filter, statement: statement}} = socket

    source_filter =
      case source_filter do
        nil -> :quotes
        :quotes -> nil
        :users -> :quotes
      end

    socket =
      socket
      |> assign(:source_filter, source_filter)
      |> load_statement_and_likes(statement)

    {:noreply, socket}
  end

  def handle_event("filter-users", _, socket) do
    %{assigns: %{source_filter: source_filter, statement: statement}} = socket

    source_filter =
      case source_filter do
        nil -> :users
        :quotes -> :users
        :users -> nil
      end

    socket =
      socket
      |> assign(:source_filter, source_filter)
      |> load_statement_and_likes(statement)

    {:noreply, socket}
  end

  def handle_event("filter-answer", %{"answer" => answer}, socket) do
    %{assigns: %{statement: statement}} = socket

    socket =
      socket
      |> assign(:answer_filter, answer)
      |> load_statement_and_likes(statement)

    {:noreply, socket}
  end

  def handle_event("close-vote-auth-modal", _, socket) do
    socket =
      socket
      |> assign(:show_vote_auth_modal, false)
      |> assign(:pending_vote_prompt, nil)

    {:noreply, socket}
  end

  def handle_event("toggle-country-results", %{"statement_id" => statement_id}, socket) do
    statement_id = String.to_integer(statement_id)

    socket =
      if socket.assigns.show_country_results do
        assign(socket, :show_country_results, false)
      else
        socket
        |> assign(:show_country_results, true)
        |> assign(
          :country_vote_frequencies,
          VoteFrequencies.get_by_country(statement_id, socket.assigns.country_results_filters)
        )
      end

    {:noreply, socket}
  end

  def handle_event(
        "toggle-country-results-filter",
        %{"filter" => filter, "statement_id" => statement_id},
        socket
      ) do
    filters =
      VoteFrequencies.toggle_country_filter(socket.assigns.country_results_filters, filter)

    statement_id = String.to_integer(statement_id)

    socket =
      socket
      |> assign(:show_country_results, true)
      |> assign(:country_results_filters, filters)
      |> assign(:country_vote_frequencies, VoteFrequencies.get_by_country(statement_id, filters))

    {:noreply, socket}
  end

  @impl true

  def handle_info(:reload, socket) do
    socket = load_statement_and_likes(socket, socket.assigns.statement)

    {:noreply, socket}
  end

  def handle_info({:put_flash, kind, msg}, socket) do
    socket =
      socket
      |> clear_flash()
      |> put_flash(kind, msg)

    {:noreply, socket}
  end

  def handle_info({:require_auth_to_vote, payload}, socket) do
    {:noreply, record_guest_vote(socket, payload)}
  end

  def handle_info({:opinion_like_changed, opinion_id, liked}, socket) do
    liked_opinion_ids =
      if liked do
        Enum.uniq([opinion_id | socket.assigns.liked_opinion_ids])
      else
        Enum.reject(socket.assigns.liked_opinion_ids, &(&1 == opinion_id))
      end

    {:noreply, assign(socket, :liked_opinion_ids, liked_opinion_ids)}
  end

  def handle_info({:voted, _vote}, socket) do
    statement = socket.assigns.statement

    socket =
      socket
      |> load_statement_and_likes(statement)
      |> maybe_reload_country_vote_frequencies()

    vote = socket.assigns.current_user_vote
    socket = assign(socket, editing: !vote || !vote.opinion_id)

    {:noreply, socket}
  end

  def handle_info({YouCongressWeb.StatementLive.FormComponent, {:saved, statement}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Statement updated successfully")
     |> push_patch(to: ~p"/p/#{statement.slug}")}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @spec page_title(atom, binary) :: binary
  defp page_title(:show, statement_title), do: statement_title
  defp page_title(:edit, _), do: "Edit Poll"

  # Depends on vote_frequencies and quotes_votes_count, so it must run
  # after VotesLoader has populated the assigns.
  defp assign_page_description(socket) do
    %{statement: statement, vote_frequencies: vote_frequencies, quotes_votes_count: quotes_count} =
      socket.assigns

    assign(
      socket,
      :page_description,
      SEO.statement_description(statement.title, vote_frequencies, quotes_count)
    )
  end

  defp load_random_statements(socket, statement_id) do
    random_statements_from_main_hall =
      case HallsStatements.get_main_hall(statement_id) do
        nil ->
          []

        main_hall ->
          statements =
            HallsStatements.get_random_statements_from_hall(main_hall.name, 5, [statement_id])

          if Enum.empty?(statements), do: [], else: [{main_hall, statements}]
      end

    assign(socket, :random_statements_from_main_hall, random_statements_from_main_hall)
  end

  defp maybe_reload_country_vote_frequencies(%{assigns: %{show_country_results: true}} = socket) do
    assign(
      socket,
      :country_vote_frequencies,
      VoteFrequencies.get_by_country(
        socket.assigns.statement.id,
        socket.assigns.country_results_filters
      )
    )
  end

  defp maybe_reload_country_vote_frequencies(socket), do: socket

  defp load_statement_and_likes(socket, statement) do
    socket
    |> VotesLoader.load_statement_and_votes(statement.id)
    |> assign(
      :liked_opinion_ids,
      Likes.get_liked_opinion_ids(socket.assigns.current_user, statement)
    )
  end
end
