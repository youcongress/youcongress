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

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    %{assigns: %{current_user: current_user}} = socket

    if connected?(socket) do
      Track.event("View Statement", current_user)
    end

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug}, _, socket) do
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
      |> assign(reload: false)
      |> assign(full_width: true)
      |> assign(:regenerating_opinion_id, nil)
      |> assign(:find_quotes_in_progress, QuotatorAI.check_polling_job_status(statement.id))
      |> assign(:source_filter, nil)
      |> assign(:answer_filter, nil)
      |> VotesLoader.load_statement_and_votes(statement.id)
      |> load_random_statements(statement.id)
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user, statement))

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

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}

  def handle_event("find-sourced-quotes", %{"statement_id" => statement_id}, socket) do
    statement_id = String.to_integer(statement_id)
    current_user = socket.assigns.current_user

    cond do
      is_nil(current_user) ->
        {:noreply, put_flash(socket, :error, "Please log in to find quotes.")}

      not Permissions.can_generate_ai_votes?(current_user) ->
        {:noreply, put_flash(socket, :error, "You don't have permission to find quotes.")}

      true ->
        %{statement_id: statement_id, user_id: current_user.id, find_n_quotes: 10}
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
      |> VotesLoader.load_statement_and_votes(statement.id)
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
      |> VotesLoader.load_statement_and_votes(statement.id)

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
      |> VotesLoader.load_statement_and_votes(statement.id)

    {:noreply, socket}
  end

  def handle_event("filter-answer", %{"answer" => answer}, socket) do
    %{assigns: %{statement: statement}} = socket

    socket =
      socket
      |> assign(:answer_filter, answer)
      |> VotesLoader.load_statement_and_votes(statement.id)

    {:noreply, socket}
  end

  @impl true

  def handle_info(:reload, socket) do
    socket = VotesLoader.load_statement_and_votes(socket, socket.assigns.statement.id)

    {:noreply, socket}
  end

  def handle_info({:put_flash, kind, msg}, socket) do
    socket =
      socket
      |> clear_flash()
      |> put_flash(kind, msg)

    {:noreply, socket}
  end

  def handle_info({:voted, vote}, socket) do
    {:noreply, assign(socket, :current_user_vote, vote)}
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

  defp load_random_statements(socket, statement_id) do
    statement = Statements.get_statement!(statement_id, preload: [:halls])

    {random_statements_by_hall, _} =
      statement.halls
      |> Enum.reduce({[], [statement_id]}, fn hall, {acc_halls, exclude_ids} ->
        statements = HallsStatements.get_random_statements(hall.name, 5, exclude_ids)
        new_exclude_ids = exclude_ids ++ Enum.map(statements, & &1.id)
        {acc_halls ++ [{hall, statements}], new_exclude_ids}
      end)

    random_statements_by_hall =
      Enum.reject(random_statements_by_hall, fn {_hall, statements} -> Enum.empty?(statements) end)

    assign(socket, :random_statements_by_hall, random_statements_by_hall)
  end
end
