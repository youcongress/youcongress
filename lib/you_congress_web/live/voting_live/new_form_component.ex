defmodule YouCongressWeb.VotingLive.NewFormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Votings

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form for={@form} id="voting-form" phx-target={@myself} phx-change="validate" phx-submit="save">
        <div>
          <.input field={@form[:title]} type="text" placeholder="What shall we vote?" />
          <.button class="mt-4" phx-disable-with="Creating...">Create</.button>
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
     |> assign(voting: voting)}
  end

  @impl true
  def handle_event("validate", %{"voting" => voting_params}, socket) do
    changeset =
      socket.assigns.voting
      |> Votings.change_voting(voting_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"voting" => voting_params}, socket) do
    case Votings.create_voting(voting_params) do
      {:ok, voting} ->
        notify_parent({:saved, voting})

        {:noreply,
         socket
         |> put_flash(:info, "Voting created successfully")
         |> redirect(to: ~p"/votings/#{voting.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
