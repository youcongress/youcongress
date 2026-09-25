defmodule YouCongressWeb.ReconsiderLive.New do
  use YouCongressWeb, :live_view

  alias YouCongress.Authors
  alias YouCongress.Reconsiderations
  alias YouCongress.Statements

  @search_limit 8
  @minimum_query_length 2
  @maximum_statements 3

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    if is_nil(socket.assigns.current_user.author.username) do
      {:ok,
       socket
       |> put_flash(:error, "Choose a YouCongress username before creating a Reconsider page.")
       |> redirect(to: ~p"/settings")}
    else
      mount_form(socket)
    end
  end

  defp mount_form(socket) do
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
     |> assign(:maximum_statements, @maximum_statements)
     |> assign(:form, form)
     |> assign(:error_message, nil)
     |> assign(:selected_statements, [])
     |> assign(:statement_query, "")
     |> assign(:statement_results, [])
     |> assign(:statement_selected_index, 0)
     |> assign(:selected_delegates, [])
     |> assign(:delegate_query, "")
     |> assign(:delegate_results, [])
     |> assign(:delegate_selected_index, 0)}
  end

  @impl true
  def handle_event("search-statements", %{"statement_search" => query}, socket) do
    results =
      if searchable?(query) and length(socket.assigns.selected_statements) < @maximum_statements do
        selected_ids = Enum.map(socket.assigns.selected_statements, & &1.id)

        Statements.list_statements(
          search: String.trim(query),
          exclude_ids: selected_ids,
          order: :opinion_likes_count_desc,
          limit: @search_limit
        )
      else
        []
      end

    {:noreply,
     socket
     |> assign(:statement_query, query)
     |> assign(:statement_results, results)
     |> assign(:statement_selected_index, 0)}
  end

  def handle_event("add-statement", %{"id" => id}, socket) do
    with true <- length(socket.assigns.selected_statements) < @maximum_statements,
         {:ok, id} <- parse_id(id),
         statement when not is_nil(statement) <-
           Enum.find(socket.assigns.statement_results, &(&1.id == id)) do
      {:noreply, select_statement(socket, statement)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("statement-keydown", %{"key" => "ArrowDown"}, socket) do
    {:noreply,
     update_selected_index(
       socket,
       :statement_selected_index,
       socket.assigns.statement_results,
       1
     )}
  end

  def handle_event("statement-keydown", %{"key" => "ArrowUp"}, socket) do
    {:noreply,
     update_selected_index(
       socket,
       :statement_selected_index,
       socket.assigns.statement_results,
       -1
     )}
  end

  def handle_event("statement-keydown", %{"key" => "Enter"}, socket) do
    case active_result(socket.assigns.statement_results, socket.assigns.statement_selected_index) do
      nil -> {:noreply, socket}
      statement -> {:noreply, select_statement(socket, statement)}
    end
  end

  def handle_event("statement-keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :statement_results, [])}
  end

  def handle_event("statement-keydown", _params, socket), do: {:noreply, socket}

  def handle_event("remove-statement", %{"id" => id}, socket) do
    case parse_id(id) do
      {:ok, id} ->
        {:noreply,
         update(socket, :selected_statements, &Enum.reject(&1, fn item -> item.id == id end))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("search-delegates", %{"delegate_search" => query}, socket) do
    results =
      if searchable?(query) do
        excluded_ids = [socket.assigns.current_user.author_id | selected_delegate_ids(socket)]

        Authors.list_authors(
          search: String.trim(query),
          order_by_search_relevance: query,
          limit: @search_limit
        )
        |> Enum.reject(&(&1.id in excluded_ids))
      else
        []
      end

    {:noreply,
     socket
     |> assign(:delegate_query, query)
     |> assign(:delegate_results, results)
     |> assign(:delegate_selected_index, 0)}
  end

  def handle_event("add-delegate", %{"id" => id}, socket) do
    with {:ok, id} <- parse_id(id),
         delegate when not is_nil(delegate) <-
           Enum.find(socket.assigns.delegate_results, &(&1.id == id)) do
      {:noreply, select_delegate(socket, delegate)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delegate-keydown", %{"key" => "ArrowDown"}, socket) do
    {:noreply,
     update_selected_index(
       socket,
       :delegate_selected_index,
       socket.assigns.delegate_results,
       1
     )}
  end

  def handle_event("delegate-keydown", %{"key" => "ArrowUp"}, socket) do
    {:noreply,
     update_selected_index(
       socket,
       :delegate_selected_index,
       socket.assigns.delegate_results,
       -1
     )}
  end

  def handle_event("delegate-keydown", %{"key" => "Enter"}, socket) do
    case active_result(socket.assigns.delegate_results, socket.assigns.delegate_selected_index) do
      nil -> {:noreply, socket}
      delegate -> {:noreply, select_delegate(socket, delegate)}
    end
  end

  def handle_event("delegate-keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :delegate_results, [])}
  end

  def handle_event("delegate-keydown", _params, socket), do: {:noreply, socket}

  def handle_event("remove-delegate", %{"id" => id}, socket) do
    case parse_id(id) do
      {:ok, id} ->
        {:noreply,
         update(socket, :selected_delegates, &Enum.reject(&1, fn item -> item.id == id end))}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save", %{"reconsideration" => params}, socket) do
    params =
      params
      |> Map.put("statement_refs", selected_statement_refs(socket))
      |> Map.put("delegate_refs", selected_delegate_refs(socket))

    case Reconsiderations.create_from_refs(socket.assigns.current_user, params) do
      {:ok, reconsideration} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your Reconsider page is ready to share.")
         |> push_navigate(
           to: ~p"/@#{socket.assigns.current_user.author.username}/r/#{reconsideration.slug}"
         )}

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

  defp searchable?(query), do: String.length(String.trim(query)) >= @minimum_query_length

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error

  defp select_statement(socket, statement) do
    socket
    |> update(:selected_statements, &(&1 ++ [statement]))
    |> assign(:statement_query, "")
    |> assign(:statement_results, [])
    |> assign(:statement_selected_index, 0)
    |> assign(:error_message, nil)
    |> push_event("clear-autocomplete", %{id: "statement-search"})
  end

  defp select_delegate(socket, delegate) do
    socket
    |> update(:selected_delegates, &(&1 ++ [delegate]))
    |> assign(:delegate_query, "")
    |> assign(:delegate_results, [])
    |> assign(:delegate_selected_index, 0)
    |> push_event("clear-autocomplete", %{id: "delegate-search"})
  end

  defp update_selected_index(socket, key, [], _change), do: assign(socket, key, 0)

  defp update_selected_index(socket, key, results, change) do
    current_index = Map.fetch!(socket.assigns, key)
    next_index = (current_index + change) |> max(0) |> min(length(results) - 1)
    assign(socket, key, next_index)
  end

  defp active_result(results, index), do: Enum.at(results, index)

  defp active_option_id(prefix, results, index) do
    case active_result(results, index) do
      nil -> nil
      result -> "#{prefix}-#{result.id}"
    end
  end

  defp selected_statement_refs(socket) do
    Enum.map_join(socket.assigns.selected_statements, "\n", &to_string(&1.id))
  end

  defp selected_delegate_refs(socket) do
    Enum.map_join(socket.assigns.selected_delegates, "\n", &to_string(&1.id))
  end

  defp selected_delegate_ids(socket), do: Enum.map(socket.assigns.selected_delegates, & &1.id)

  defp author_name(author),
    do: author.name || author.username || author.twitter_username || "YouCongress author"

  defp author_username(%{username: username}) when is_binary(username), do: "@#{username}"

  defp author_username(%{twitter_username: username}) when is_binary(username),
    do: "@#{username}"

  defp author_username(_author), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl px-4 py-8 sm:px-6">
      <div class="mb-8">
        <h1 class="text-3xl font-bold tracking-tight text-gray-900">Create a Reconsider page</h1>
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
        <div id="statement-picker" class="space-y-3">
          <label for="statement-search" class="block text-sm font-semibold leading-6 text-zinc-800">
            YouCongress statements (1–3)
          </label>

          <div :if={@selected_statements != []} id="selected-statements" class="space-y-2">
            <div
              :for={statement <- @selected_statements}
              id={"selected-statement-#{statement.id}"}
              class="flex items-start justify-between gap-3 rounded-lg border border-indigo-200 bg-indigo-50 px-3 py-2"
            >
              <span class="text-sm text-gray-900">{statement.title}</span>
              <button
                type="button"
                phx-click="remove-statement"
                phx-value-id={statement.id}
                aria-label={"Remove #{statement.title}"}
                class="shrink-0 text-lg leading-5 text-indigo-700 hover:text-indigo-900"
              >
                ×
              </button>
            </div>
          </div>

          <div :if={length(@selected_statements) < @maximum_statements} class="relative">
            <input
              id="statement-search"
              name="statement_search"
              type="search"
              value={@statement_query}
              placeholder="Start typing a statement…"
              autocomplete="off"
              role="combobox"
              aria-autocomplete="list"
              aria-controls="statement-results"
              aria-expanded={to_string(@statement_results != [])}
              aria-activedescendant={
                active_option_id(
                  "statement-result",
                  @statement_results,
                  @statement_selected_index
                )
              }
              phx-change="search-statements"
              phx-keydown="statement-keydown"
              phx-debounce="250"
              onkeydown="if(['ArrowDown','ArrowUp','Enter','Escape'].includes(event.key)) event.preventDefault()"
              class="block w-full rounded-lg border-0 px-3 py-2 text-zinc-900 shadow-sm ring-1 ring-inset ring-zinc-300 placeholder:text-zinc-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
            />

            <div
              :if={@statement_results != []}
              id="statement-results"
              role="listbox"
              class="absolute z-20 mt-1 max-h-64 w-full overflow-y-auto rounded-lg border border-gray-200 bg-white p-1 shadow-lg"
            >
              <button
                :for={{statement, index} <- Enum.with_index(@statement_results)}
                id={"statement-result-#{statement.id}"}
                type="button"
                role="option"
                aria-selected={to_string(index == @statement_selected_index)}
                phx-click="add-statement"
                phx-value-id={statement.id}
                class={[
                  "block w-full rounded-md px-3 py-2 text-left text-sm text-gray-900 hover:bg-indigo-50 focus:bg-indigo-50 focus:outline-none",
                  index == @statement_selected_index && "bg-indigo-50"
                ]}
              >
                {statement.title}
              </button>
            </div>
          </div>

          <p
            :if={length(@selected_statements) == @maximum_statements}
            class="text-xs font-medium text-indigo-700"
          >
            You have selected the maximum of three statements.
          </p>
          <p
            :if={
              searchable?(@statement_query) && @statement_results == [] &&
                length(@selected_statements) < @maximum_statements
            }
            id="no-statement-results"
            class="text-xs text-gray-500"
          >
            No matching statements found.
          </p>
          <p class="text-xs text-gray-500">
            Type at least two characters, then select a statement. You can add up to three.
          </p>
        </div>

        <div id="delegate-picker" class="space-y-3">
          <label for="delegate-search" class="block text-sm font-semibold leading-6 text-zinc-800">
            People from the article/video viewers may delegate to (optional)
          </label>

          <div :if={@selected_delegates != []} id="selected-delegates" class="flex flex-wrap gap-2">
            <div
              :for={delegate <- @selected_delegates}
              id={"selected-delegate-#{delegate.id}"}
              class="inline-flex items-center gap-2 rounded-full border border-indigo-200 bg-indigo-50 px-3 py-1.5 text-sm text-gray-900"
            >
              <span>{author_name(delegate)}</span>
              <span :if={author_username(delegate)} class="text-gray-500">
                {author_username(delegate)}
              </span>
              <button
                type="button"
                phx-click="remove-delegate"
                phx-value-id={delegate.id}
                aria-label={"Remove #{author_name(delegate)}"}
                class="text-lg leading-4 text-indigo-700 hover:text-indigo-900"
              >
                ×
              </button>
            </div>
          </div>

          <div class="relative">
            <input
              id="delegate-search"
              name="delegate_search"
              type="search"
              value={@delegate_query}
              placeholder="Search by name, username, or bio…"
              autocomplete="off"
              role="combobox"
              aria-autocomplete="list"
              aria-controls="delegate-results"
              aria-expanded={to_string(@delegate_results != [])}
              aria-activedescendant={
                active_option_id(
                  "delegate-result",
                  @delegate_results,
                  @delegate_selected_index
                )
              }
              phx-change="search-delegates"
              phx-keydown="delegate-keydown"
              phx-debounce="250"
              onkeydown="if(['ArrowDown','ArrowUp','Enter','Escape'].includes(event.key)) event.preventDefault()"
              class="block w-full rounded-lg border-0 px-3 py-2 text-zinc-900 shadow-sm ring-1 ring-inset ring-zinc-300 placeholder:text-zinc-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
            />

            <div
              :if={@delegate_results != []}
              id="delegate-results"
              role="listbox"
              class="absolute z-20 mt-1 max-h-72 w-full overflow-y-auto rounded-lg border border-gray-200 bg-white p-1 shadow-lg"
            >
              <button
                :for={{delegate, index} <- Enum.with_index(@delegate_results)}
                id={"delegate-result-#{delegate.id}"}
                type="button"
                role="option"
                aria-selected={to_string(index == @delegate_selected_index)}
                phx-click="add-delegate"
                phx-value-id={delegate.id}
                class={[
                  "block w-full rounded-md px-3 py-2 text-left hover:bg-indigo-50 focus:bg-indigo-50 focus:outline-none",
                  index == @delegate_selected_index && "bg-indigo-50"
                ]}
              >
                <span class="flex items-baseline gap-2">
                  <span class="text-sm font-medium text-gray-900">{author_name(delegate)}</span>
                  <span :if={author_username(delegate)} class="text-xs text-gray-500">
                    {author_username(delegate)}
                  </span>
                </span>
                <span :if={delegate.bio} class="mt-0.5 line-clamp-2 block text-xs text-gray-500">
                  {delegate.bio}
                </span>
              </button>
            </div>
          </div>

          <p
            :if={searchable?(@delegate_query) && @delegate_results == []}
            id="no-delegate-results"
            class="text-xs text-gray-500"
          >
            No matching people found.
          </p>
        </div>

        <:actions>
          <.button phx-disable-with="Creating…">Create Reconsider page</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
