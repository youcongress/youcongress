defmodule YouCongressWeb.StatementLive.NewFormComponent do
  use YouCongressWeb, :live_component

  require Logger

  alias YouCongress.Statements
  alias YouCongress.Statements.TitleRewording
  alias YouCongress.Track

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto bg-white rounded-xl shadow-sm border border-gray-100 p-6 transition-all hover:shadow-md">
      <.form
        for={@form}
        id="statement-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="ai-validate"
        class="space-y-6"
      >
        <div>
          <h2 class="text-lg font-semibold text-gray-900 mb-2">
            What policy proposal or claim would you like to analyze?
          </h2>
          <p class="text-sm mb-4">
            <span>
              You'll be able to add <strong>sourced quotes</strong> from experts and public figures.
            </span>
          </p>
          <p class="text-sm text-gray-600 mb-4">
            Your prompt will be reviewed by AI to ensure clarity and offer you suggestions before publishing.
          </p>
          <div class="relative">
            <.input
              field={@form[:title]}
              type="text"
              maxlength="150"
              placeholder="E.g. Build a CERN for AI"
              class="w-full px-4 py-3 rounded-lg border border-gray-300 focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 transition-colors"
            />
          </div>

          <%= if @suggested_titles != [] do %>
            <div class="mt-6 space-y-4">
              <div class="bg-indigo-50 rounded-lg p-4">
                <h4 class="font-medium text-indigo-900 mb-2">Suggested Questions</h4>
                <p class="text-sm text-indigo-700 mb-3">
                  Choose one of these clear yes/no questions, or click
                  <button
                    type="submit"
                    class="text-indigo-600 font-medium hover:text-indigo-500 underline"
                  >
                    generate 3 more
                  </button>
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
                        {suggested_title}
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
                phx-disable-with="Validating..."
              >
                <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
                Next
              </button>
              <.link
                :if={@cancel_link?}
                href="#"
                phx-click="toggle-new-poll"
                class="mt-2 inline-block text-sm text-gray-500 hover:text-gray-700"
              >
                Cancel
              </.link>
            </div>
          <% end %>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{statement: statement} = assigns, socket) do
    changeset = Statements.change_statement(statement)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)
     |> assign(statement: statement, suggested_titles: [])}
  end

  @impl true
  def handle_event("validate", %{"statement" => statement_params}, socket) do
    changeset =
      socket.assigns.statement
      |> Statements.change_statement(statement_params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign_form(changeset)
      |> assign(suggested_titles: [])

    {:noreply, socket}
  end

  def handle_event("ai-validate", %{"statement" => statement}, socket) do
    %{assigns: %{current_user: current_user}} = socket
    Track.event("Validate New Statement", current_user)

    # suggested_titles = [
    #   "Should we increase investment in nuclear energy research?",
    #   "Shall we consider nuclear energy as a viable alternative to fossil fuels?",
    #   "Could nuclear energy be a key solution for reducing global carbon emissions?"
    # ]

    # {:noreply, assign(socket, suggested_titles: suggested_titles)}

    if statement["title"] == "" do
      changeset =
        socket.assigns.statement
        |> Statements.change_statement(%{})
        |> Map.put(:action, :validate)

      {:noreply, assign_form(socket, changeset)}
    else
      case TitleRewording.generate_rewordings(statement["title"], :"gpt-4o") do
        {:ok, suggested_titles, _} ->
          {:noreply, assign(socket, suggested_titles: suggested_titles)}

        {:error, error} ->
          Logger.error("Error validating the statement: #{inspect(error)}")
          notify_parent({:put_flash, :error, "Error validating the statement"})
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

    case Statements.create_statement(%{title: suggested_title, user_id: user_id}) do
      {:ok, statement} ->
        Track.event("Create Statement", current_user)
        notify_parent({:put_flash, :info, "Statement created successfully"})

        {:noreply, redirect(socket, to: ~p"/p/#{statement.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
