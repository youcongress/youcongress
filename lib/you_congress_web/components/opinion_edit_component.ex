defmodule YouCongressWeb.OpinionEditComponent do
  @moduledoc """
  A reusable component for editing opinions/quotes with their associated voting positions.
  """
  use YouCongressWeb, :live_component

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes

  @impl true
  def update(%{opinion: opinion} = assigns, socket) do
    changeset =
      Opinion.changeset(opinion, %{
        content: opinion.content,
        year: opinion.year,
        source_url: opinion.source_url,
        author_id: opinion.author_id
      })

    form = to_form(changeset)

    # Load available authors for the dropdown
    authors = YouCongress.Authors.list_authors()

    # Initialize author search with current author name
    current_author_name = if opinion.author, do: opinion.author.name, else: ""

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:authors, authors)
     |> assign(:author_search, current_author_name)
     |> assign(:filtered_authors, authors)
     |> assign(:show_author_dropdown, false)
     |> assign(:selected_author_id, opinion.author_id)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    # Extract opinion params, filtering out vote-related params
    opinion_params =
      case params do
        %{"opinion" => opinion} ->
          opinion

        _ ->
          params
          |> Map.drop(["quote_id", "opinion_id"])
          |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "vote_") end)
          |> Map.new()
      end

    # Get the current opinion being edited
    opinion = socket.assigns.opinion

    changeset =
      (opinion || %Opinion{})
      |> Opinion.changeset(opinion_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", params, socket) do
    opinion_id = socket.assigns.opinion.id

    # Extract opinion params, filtering out vote-related params
    opinion_params =
      case params do
        %{"opinion" => opinion} ->
          # If we have a selected_author_id in the component state, use it
          if socket.assigns.selected_author_id do
            Map.put(opinion, "author_id", socket.assigns.selected_author_id)
          else
            opinion
          end

        # Handle simple comment form
        %{"comment" => comment} ->
          %{"content" => comment}

        _ ->
          params
          |> Map.drop(["quote_id", "opinion_id"])
          |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "vote_") end)
          |> Map.new()
      end

    opinion = Opinions.get_opinion!(opinion_id, preload: [:author, :votings])

    case Opinions.update_opinion(opinion, opinion_params) do
      {:ok, updated_opinion} ->
        # Update votes if they were changed (only for full form mode)
        if socket.assigns[:show_voting_positions] do
          update_author_votes(params, opinion)
        end

        # If author was changed, update the associated votes' author_id
        if socket.assigns.selected_author_id &&
             socket.assigns.selected_author_id != opinion.author_id do
          Votes.update_author_for_opinion_votes(opinion.id, socket.assigns.selected_author_id)
        end

        # Send success message to parent
        send(self(), {:opinion_updated, updated_opinion})

        {:noreply, socket}

      {:error, changeset} ->
        # Send error message to parent
        send(self(), {:opinion_update_error, changeset})

        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    send(self(), :opinion_edit_cancelled)
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_author", %{"author_search" => search_term}, socket) do
    filtered_authors =
      if String.trim(search_term) == "" do
        socket.assigns.authors
      else
        socket.assigns.authors
        |> Enum.filter(fn author ->
          String.contains?(String.downcase(author.name || ""), String.downcase(search_term))
        end)
      end

    {:noreply,
     socket
     |> assign(:author_search, search_term)
     |> assign(:filtered_authors, filtered_authors)
     |> assign(:show_author_dropdown, true)}
  end

  @impl true
  def handle_event("select_author", %{"author_id" => author_id}, socket) do
    selected_author = Enum.find(socket.assigns.authors, &(&1.id == String.to_integer(author_id)))

    # Update the form with the new author_id
    opinion_params = %{
      "content" => socket.assigns.opinion.content,
      "year" => socket.assigns.opinion.year,
      "source_url" => socket.assigns.opinion.source_url,
      "author_id" => selected_author.id
    }

    changeset =
      socket.assigns.opinion
      |> Opinion.changeset(opinion_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:author_search, selected_author.name)
     |> assign(:show_author_dropdown, false)
     |> assign(:selected_author_id, selected_author.id)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("toggle_author_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_author_dropdown, !socket.assigns.show_author_dropdown)}
  end

  @impl true
  def handle_event("close_author_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_author_dropdown, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        phx-target={@myself}
        phx-submit="save"
        phx-change="validate"
        class="space-y-4"
      >
        <input type="hidden" name="opinion_id" value={@opinion.id} />
        
    <!-- Opinion Content -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">
            {if assigns[:show_content_label], do: assigns[:content_label] || "Quote Content", else: ""}
          </label>
          <.input
            field={@form[:content]}
            type="textarea"
            rows="4"
            class="w-full"
          />
        </div>
        
    <!-- Year -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Year</label>
          <.input
            field={@form[:year]}
            type="number"
            placeholder="e.g., 2020"
            class="w-32"
          />
        </div>
        
    <!-- Source URL -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Source URL</label>
          <.input
            field={@form[:source_url]}
            type="url"
            placeholder="https://example.com/source"
            class="w-full"
          />
        </div>
        
    <!-- Author Selection -->
        <%= if assigns[:show_author] do %>
          <div class="relative">
            <label class="block text-sm font-medium text-gray-700 mb-1">Author</label>
            <div class="relative">
              <input
                type="text"
                name="author_search"
                value={@author_search}
                phx-target={@myself}
                phx-change="search_author"
                phx-click="toggle_author_dropdown"
                placeholder="Search for an author..."
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              />
              <%= if @show_author_dropdown do %>
                <div
                  class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm"
                  phx-click-away="close_author_dropdown"
                  phx-target={@myself}
                >
                  <%= if @filtered_authors == [] do %>
                    <div class="cursor-default select-none relative py-2 pl-3 pr-9 text-gray-500">
                      No authors found
                    </div>
                  <% else %>
                    <%= for author <- @filtered_authors do %>
                      <div
                        class="cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-indigo-50 hover:text-indigo-900"
                        phx-click="select_author"
                        phx-value-author_id={author.id}
                        phx-target={@myself}
                        id={"author_option_#{author.id}"}
                      >
                        <span class="font-normal block truncate">{author.name}</span>
                        <%= if @selected_author_id == author.id do %>
                          <span class="absolute inset-y-0 right-0 flex items-center pr-4">
                            <svg
                              class="h-5 w-5 text-indigo-600"
                              viewBox="0 0 20 20"
                              fill="currentColor"
                            >
                              <path
                                fill-rule="evenodd"
                                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                                clip-rule="evenodd"
                              />
                            </svg>
                          </span>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        
    <!-- Voting Positions -->
        <%= if assigns[:show_voting_positions] && @opinion.votings && @opinion.votings != [] do %>
          <div class="space-y-3">
            <label class="block text-sm font-medium text-gray-700">Author's Position</label>
            <%= for voting <- @opinion.votings do %>
              <div class="border rounded p-3 bg-gray-50">
                <div class="text-sm font-medium mb-2">
                  <a href={~p"/p/#{voting.slug}"} class="text-indigo-600 hover:underline">
                    {voting.title}
                  </a>
                </div>
                <select
                  name={"vote_#{voting.id}"}
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                >
                  <%= for {label, value} <- [{"For", "for"}, {"Against", "against"}, {"Abstain", "abstain"}] do %>
                    <option
                      value={value}
                      selected={
                        Map.get(voting, :author_vote) && voting.author_vote.answer &&
                          to_string(voting.author_vote.answer) == value
                      }
                    >
                      {label}
                    </option>
                  <% end %>
                </select>
              </div>
            <% end %>
          </div>
        <% end %>
        
    <!-- Form Actions -->
        <div class="flex gap-2 pt-2">
          <button
            type="submit"
            class={[
              "px-3 py-1 text-white rounded hover:bg-blue-700",
              assigns[:save_button_class] || "bg-blue-600"
            ]}
          >
            {assigns[:save_button_text] || "Save"}
          </button>
          <button
            type="button"
            phx-click="cancel"
            phx-target={@myself}
            class={[
              "px-3 py-1 text-gray-700 rounded hover:bg-gray-400",
              assigns[:cancel_button_class] || "bg-gray-300"
            ]}
          >
            {assigns[:cancel_button_text] || "Cancel"}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  # Private helper functions
  defp update_author_votes(params, opinion) do
    if opinion.author do
      # Process vote updates for each voting
      Enum.each(opinion.votings, fn voting ->
        vote_param_key = "vote_#{voting.id}"

        if Map.has_key?(params, vote_param_key) do
          response = params[vote_param_key]

          if response != "" do
            # Create or update the vote
            Votes.create_or_update(%{
              voting_id: voting.id,
              author_id: opinion.author.id,
              answer: response,
              direct: true
            })
          else
            # Delete the vote if "No position" is selected
            case Votes.get_by(%{voting_id: voting.id, author_id: opinion.author.id}) do
              nil -> :ok
              vote -> Votes.delete_vote(vote)
            end
          end
        end
      end)
    end
  end
end
