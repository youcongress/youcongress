defmodule YouCongressWeb.VotingLive.Index.OpinateComponent do
  @moduledoc """
  Render current vote and form to create and edit an opinion
  """
  use YouCongressWeb, :live_component

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers

  @impl true
  def update(assigns, socket) do
    form =
      (assigns.opinion || %Opinion{})
      |> Opinions.change_opinion()
      |> to_form()

    {:ok,
     socket
     |> assign_new(:form, fn -> form end)
     |> assign(:current_user, assigns.current_user)
     |> assign(:vote, assigns.vote)
     |> assign(:opinion, assigns.opinion)
     |> assign(:voting, assigns.voting)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @current_user do %>
        <.form
          for={@form}
          id={"v#{@voting.id}-opinion-form"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          Why did you vote that way?
          <div class="text-xs text-gray-500 pb-0 mb-0">
            Strong arguments may lead others to delegate to you.
          </div>
          <div class="mb-4">
            <textarea
              name="opinion[content]"
              rows="4"
              placeholder={
                if @current_user,
                  do: "Add your comment...",
                  else: "Log in to comment..."
              }
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              phx-debounce="300"
              disabled={is_nil(@current_user)}
            ><%= @form[:content].value %></textarea>
            <%= for error <- Keyword.get_values(@form.errors, :content) do %>
              <div class="mt-1 text-sm text-red-600"><%= translate_error(error) %></div>
            <% end %>
          </div>
          <div class="flex items-center space-x-2">
            <button
              type="submit"
              class="inline-flex justify-center rounded-md border border-transparent bg-indigo-600 py-2 px-4 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed"
              phx-disable-with="Saving..."
              disabled={is_nil(@current_user)}
            >
              <%= if @form.data.id, do: "Update", else: "Publish" %> Arguments
            </button>
            <%= if @form.data.id do %>
              <.link
                href="#"
                phx-click="delete"
                phx-target={@myself}
                class="text-sm text-red-600 hover:text-red-800"
              >
                Delete
              </.link>
            <% else %>
              <%= if @form[:content].value && @form[:content].value != "" do %>
                <.link
                  href="#"
                  phx-click="cancel"
                  phx-target={@myself}
                  class="text-sm text-gray-600 hover:text-gray-800"
                >
                  Cancel
                </.link>
              <% end %>
            <% end %>
          </div>
        </.form>
      <% else %>
        <.link href={~p"/p/#{@voting.slug}"} class="underline">Read comments</.link>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"opinion" => opinion_params}, socket) do
    form =
      socket.assigns.form.data
      |> Opinions.change_opinion(opinion_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"opinion" => opinion_params}, socket) do
    action = if socket.assigns.form.data.id, do: :edit, else: :new
    save_opinion(socket, action, opinion_params)
  end

  def handle_event("cancel", _, socket) do
    form =
      %Opinion{}
      |> Opinions.change_opinion()
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("delete", _, socket) do
    case Opinions.delete_opinion(socket.assigns.opinion) do
      {:ok, _deleted_opinion} ->
        form =
          %Opinion{}
          |> Opinions.change_opinion()
          |> to_form()

        send(self(), {:put_flash, :info, "Opinion deleted successfully"})
        {:noreply, assign(socket, :form, form)}

      {:error, _changeset} ->
        send(self(), {:put_flash, :error, "Failed to delete opinion"})
        {:noreply, socket}
    end
  end

  defp save_opinion(socket, :edit, %{"content" => content}) do
    %{
      assigns: %{current_user: current_user, opinion: opinion, voting: voting, vote: vote}
    } = socket

    opinion_params = %{
      "content" => content,
      "voting_id" => voting.id,
      "author_id" => current_user.author_id,
      "user_id" => current_user.id,
      "twin" => false
    }

    opinion = Opinions.get_opinion!(opinion.id)

    with {:ok, opinion} <- Opinions.update_opinion(opinion, opinion_params),
         {:ok, vote} <-
           create_or_update_vote(vote, %{
             current_user: current_user,
             voting: voting,
             opinion_id: opinion.id,
             vote: vote
           }) do
      form =
        opinion
        |> Opinions.change_opinion(opinion_params)
        |> to_form()

      send(self(), {:put_flash, :info, "Opinion updated successfully"})

      {:noreply,
       socket
       |> assign(:opinion, opinion)
       |> assign(:vote, vote)
       |> assign(:form, form)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to update opinion"})
        {:noreply, socket}
    end
  end

  defp save_opinion(socket, :new, %{"content" => content}) do
    %{
      assigns: %{current_user: current_user, voting: voting, vote: vote}
    } = socket

    opinion_params = %{
      "content" => content,
      "voting_id" => voting.id,
      "author_id" => current_user.author_id,
      "user_id" => current_user.id,
      "twin" => false
    }

    with {:ok, opinion} <- Opinions.create_opinion(opinion_params),
         {:ok, vote} <-
           create_or_update_vote(vote, %{
             current_user: current_user,
             voting: voting,
             opinion_id: opinion.id,
             vote: vote
           }) do
      form =
        opinion
        |> Opinions.change_opinion(opinion_params)
        |> to_form()

      send(self(), {:put_flash, :info, "Opinion created successfully"})

      {:noreply,
       socket
       |> assign(:opinion, opinion)
       |> assign(:vote, vote)
       |> assign(:form, form)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to create opinion"})
        {:noreply, socket}
    end
  end

  defp create_or_update_vote(nil, params) do
    Votes.create_vote(vote_params(params))
  end

  defp create_or_update_vote(vote, params) do
    vote = Votes.get_vote(vote.id)

    if vote do
      params = Map.put(vote_params(params), "vote", vote)
      Votes.update_vote(vote, params)
    else
      Votes.create_vote(vote_params(params))
    end
  end

  defp vote_params(params) do
    %{current_user: current_user, voting: voting, opinion_id: opinion_id, vote: vote} = params

    %{
      "answer_id" => (vote && vote.answer_id) || Answers.answer_id_by_response("N/A"),
      "author_id" => current_user.author_id,
      "voting_id" => voting.id,
      "opinion_id" => opinion_id,
      "twin" => false
    }
  end
end
