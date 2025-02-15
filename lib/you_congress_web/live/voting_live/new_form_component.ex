defmodule YouCongressWeb.VotingLive.NewFormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Votings
  alias YouCongress.Votings.TitleRewording
  alias YouCongress.Track
  alias YouCongress.Workers.PublicFiguresWorker

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto bg-white rounded-xl shadow-sm border border-gray-100 p-6 transition-all hover:shadow-md">
      <.form
        for={@form}
        id="voting-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="ai-validate"
        class="space-y-6"
      >
        <div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">
            What solution or problem would you like us to analyze and vote on?
          </h3>
          <p class="text-sm text-gray-600 mb-4">
            Your prompt will be reviewed by AI to ensure clarity and offer you three suggestions before publishing.
            <span class="text-indigo-600">No login required!</span>
          </p>
          <div class="relative">
            <.input
              field={@form[:title]}
              type="text"
              maxlength="150"
              placeholder="e.g., Should we use more nuclear energy?"
              class="w-full px-4 py-3 rounded-lg border border-gray-300 focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 transition-colors"
            />
          </div>

          <%= if @suggested_titles != [] do %>
            <div class="mt-6 space-y-4">
              <div class="bg-indigo-50 rounded-lg p-4">
                <h4 class="font-medium text-indigo-900 mb-2">AI-Suggested Questions</h4>
                <p class="text-sm text-indigo-700 mb-3">
                  Choose one of these clear yes/no questions, or click <button type="submit" class="text-indigo-600 font-medium hover:text-indigo-500 underline">generate 3 more</button>
                </p>
                <div class="space-y-3">
                  <%= for suggested_title <- @suggested_titles do %>
                    <div class="transform transition-all hover:scale-[1.01]">
                      <button
                        phx-click="save"
                        phx-value-suggested_title={suggested_title}
                        phx-target={@myself}
                        class="w-full text-left px-4 py-3 rounded-lg bg-white border border-indigo-200 text-gray-900 shadow-sm hover:bg-indigo-50 hover:border-indigo-300 transition-all duration-200"
                      >
                        <%= suggested_title %>
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <div class="mt-6">
              <button
                class="inline-flex items-center justify-center w-full sm:w-auto px-6 py-3 rounded-lg bg-indigo-600 text-white font-medium shadow-sm hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-600 transition-colors duration-200"
                phx-disable-with="Validating with ChatGPT..."
              >
                <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
                Generate Suggestions
              </button>
              <.link :if={@cancel_link?} href="#" phx-click="toggle-new-poll" class="mt-2 inline-block text-sm text-gray-500 hover:text-gray-700">Cancel</.link>
            </div>
          <% end %>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{voting: voting} = assigns, socket) do
    changeset = Votings.change_voting(voting)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)
     |> assign(voting: voting, suggested_titles: [])}
  end

  @impl true
  def handle_event("validate", %{"voting" => voting_params}, socket) do
    changeset =
      socket.assigns.voting
      |> Votings.change_voting(voting_params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign_form(changeset)
      |> assign(suggested_titles: [])

    {:noreply, socket}
  end

  def handle_event("ai-validate", %{"voting" => voting}, socket) do
    %{assigns: %{current_user: current_user}} = socket
    Track.event("Validate New Voting", current_user)

    # suggested_titles = [
    #   "Should we increase investment in nuclear energy research?",
    #   "Shall we consider nuclear energy as a viable alternative to fossil fuels?",
    #   "Could nuclear energy be a key solution for reducing global carbon emissions?"
    # ]

    # {:noreply, assign(socket, suggested_titles: suggested_titles)}

    if voting["title"] == "" do
      changeset =
        socket.assigns.voting
        |> Votings.change_voting(%{})
        |> Map.put(:action, :validate)

      {:noreply, assign_form(socket, changeset)}
    else
      case TitleRewording.generate_rewordings(voting["title"], :"gpt-4o") do
        {:ok, suggested_titles, _} ->
          {:noreply, assign(socket, suggested_titles: suggested_titles)}

        {:error, _} ->
          notify_parent({:put_flash, :error, "Error validating the voting"})
          {:noreply, socket}
      end
    end
  end

  def handle_event("save", %{"suggested_title" => suggested_title}, socket) do
    %{assigns: %{current_user: current_user}} = socket

    user_id =
      case current_user do
        nil -> nil
        _ -> current_user.id
      end

    case Votings.create_voting(%{title: suggested_title, user_id: user_id}) do
      {:ok, voting} ->
        %{voting_id: voting.id, current_user_author_id: current_user.author_id}
        |> PublicFiguresWorker.new()
        |> Oban.insert()

        Track.event("Create Voting", current_user)

        {:noreply,
         socket
         |> put_flash(:info, "Voting created successfully")
         |> redirect(to: ~p"/p/#{voting.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
