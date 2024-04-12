defmodule YouCongressWeb.VotingLive.NewFormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Votings
  alias YouCongress.Votings.TitleRewording

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="voting-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="ai-validate"
      >
        <div>
          Create a new question
          <div class="text-sm text-gray-600 pt-2">It needs to be a yes/no question</div>
          <.input
            field={@form[:title]}
            type="text"
            maxlength="150"
            placeholder="Should we build AI smarter than us?"
          />
          <%= if @suggested_titles != [] do %>
            <div>
              <div class="py-2">
                <div>Our AI proposes you one of these new questions based on your prompt.</div>
                <div>This guarantees that it's an understandable yes/no question in English.</div>
                <div class="pt-2">
                  Choose one of these (or click <button type="submit" class="underline">3 more</button>):
                </div>
              </div>
              <%= for suggested_title <- @suggested_titles do %>
                <div class="py-2">
                  <button
                    phx-click="save"
                    phx-value-suggested_title={suggested_title}
                    phx-target={@myself}
                    class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                  >
                    <%= suggested_title %>
                  </button>
                </div>
              <% end %>
            </div>
          <% else %>
            <div>
              <.button class="mt-4" phx-disable-with="Validating with ChatGPT. Please wait.">
                Send
              </.button>
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
    YouCongress.Track.event("Validate New Voting", current_user)

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
      case TitleRewording.generate_rewordings(voting["title"], :"gpt-4-turbo-2024-04-09") do
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

    case Votings.create_voting(%{title: suggested_title, user_id: current_user.id}) do
      {:ok, voting} ->
        %{voting_id: voting.id}
        |> YouCongress.Workers.PublicFiguresWorker.new()
        |> Oban.insert()

        YouCongress.Track.event("Create Voting", current_user)

        {:noreply,
         socket
         |> put_flash(:info, "Voting created successfully")
         |> redirect(to: ~p"/v/#{voting.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
