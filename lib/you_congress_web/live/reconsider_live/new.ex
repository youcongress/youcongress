defmodule YouCongressWeb.ReconsiderLive.New do
  use YouCongressWeb, :live_view

  alias YouCongress.Reconsiderations

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    form =
      to_form(
        %{
          "title" => "",
          "description" => "",
          "content_url" => "",
          "content_type" => "article",
          "statement_refs" => "",
          "delegate_refs" => ""
        },
        as: :reconsideration
      )

    {:ok,
     socket
     |> assign(:page_title, "Create a Reconsider page")
     |> assign(:form, form)
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_event("save", %{"reconsideration" => params}, socket) do
    case Reconsiderations.create_from_refs(socket.assigns.current_user, params) do
      {:ok, reconsideration} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your Reconsider page is ready to share.")
         |> push_navigate(to: ~p"/reconsider/#{reconsideration.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :reconsideration))
         |> assign(:error_message, changeset_error(changeset))}

      {:error, message} when is_binary(message) ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :reconsideration))
         |> assign(:error_message, message)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :reconsideration))
         |> assign(:error_message, "We could not create this page. Please try again.")}
    end
  end

  defp changeset_error(changeset) do
    case Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end) do
      errors when map_size(errors) == 0 -> "Please check the information and try again."
      errors -> errors |> Map.values() |> List.flatten() |> List.first()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl px-4 py-8 sm:px-6">
      <div class="mb-8">
        <p class="text-sm font-semibold uppercase tracking-wide text-indigo-600">For creators</p>
        <h1 class="mt-2 text-3xl font-bold tracking-tight text-gray-900">Create a Reconsider page</h1>
        <p class="mt-3 text-gray-600">
          Ask your audience what they believed before your article or video and what they believe now.
        </p>
      </div>

      <.simple_form for={@form} id="new-reconsider-form" phx-submit="save">
        <div
          :if={@error_message}
          class="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700"
        >
          {@error_message}
        </div>

        <.input field={@form[:title]} type="text" label="Title" required />
        <.input
          field={@form[:description]}
          type="textarea"
          label="Short description"
          placeholder="What should viewers consider?"
        />
        <.input field={@form[:content_url]} type="url" label="Article or video URL" required />
        <.input
          field={@form[:content_type]}
          type="select"
          label="Content type"
          options={[{"Article", "article"}, {"Video", "video"}]}
          required
        />
        <.input
          field={@form[:statement_refs]}
          type="textarea"
          label="YouCongress statements (one per line, 1–5)"
          placeholder="Paste a statement URL or slug"
          required
        />
        <p class="-mt-4 text-xs text-gray-500">
          Find existing statements in <.link navigate={~p"/explore"} class="text-indigo-600 underline">Explore</.link>.
        </p>
        <.input
          field={@form[:delegate_refs]}
          type="textarea"
          label="Other people viewers may delegate to (optional, one per line)"
          placeholder="Paste a YouCongress author URL, an @username, or an author ID"
        />
        <p class="-mt-4 text-xs text-gray-500">
          Your own YouCongress profile is included automatically.
        </p>

        <:actions>
          <.button phx-disable-with="Creating…">Create Reconsider page</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
