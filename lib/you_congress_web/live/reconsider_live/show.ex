defmodule YouCongressWeb.ReconsiderLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.Delegations
  alias YouCongress.Reconsiderations
  alias YouCongressWeb.Components.LoginButtons
  alias YouCongressWeb.SEO

  @answers [:for, :abstain, :against]
  @search_limit 8
  @minimum_query_length 2

  @impl true
  def mount(%{"username" => username, "slug" => slug}, session, socket) do
    current_user = assign_current_user(socket, session["user_token"]).assigns.current_user

    reconsideration =
      Reconsiderations.get_reconsideration_by_username_and_slug!(username, slug)

    return_to =
      ~p"/@#{reconsideration.creator.username}/r/#{reconsideration.slug}"

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:reconsideration, reconsideration)
      |> assign(:can_manage_reconsideration, manager?(current_user, reconsideration))
      |> assign(:return_to, return_to)
      |> assign(:answers, @answers)
      |> assign(:form_params, %{"answers" => %{}, "delegate_ids" => []})
      |> assign(:delegate_query, "")
      |> assign(:delegate_results, [])
      |> assign(:delegate_selected_index, 0)
      |> assign(:selected_extra_delegates, [])
      |> assign(:new_people, [])
      |> assign(:show_new_person_form, false)
      |> assign(:new_person_form, new_person_form())
      |> assign(:new_person_error, nil)
      |> assign(:show_auth, false)
      |> assign(:pending_actions, nil)
      |> assign(:page_title, reconsideration.title)
      |> assign(
        :canonical_url,
        url(~p"/@#{reconsideration.creator.username}/r/#{reconsideration.slug}")
      )
      |> assign(
        :page_description,
        reconsideration.description || default_description(reconsideration)
      )
      |> assign(:page_image, url(~p"/images/social-reconsider-v2.png"))
      |> assign(
        :page_image_alt,
        "Reconsider by YouCongress: measure how articles and videos change minds"
      )
      |> assign(:page_image_width, 1200)
      |> assign(:page_image_height, 630)
      |> assign_participation()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    if socket.assigns.can_manage_reconsideration and params["results"] == "true" do
      {:noreply,
       socket
       |> assign(:show_results, true)
       |> assign(:stats, Reconsiderations.stats(socket.assigns.reconsideration))}
    else
      {:noreply,
       socket
       |> assign(:show_results, socket.assigns.completed)
       |> assign(:stats, if(socket.assigns.completed, do: socket.assigns.stats, else: nil))}
    end
  end

  @impl true
  def handle_event("submit", %{"response" => params}, socket) do
    params = normalize_form_params(params, socket)

    if complete?(params, socket.assigns.reconsideration) do
      submit_or_authenticate(socket, params)
    else
      {:noreply,
       socket
       |> assign(:form_params, params)
       |> assign(:show_auth, false)
       |> put_flash(:error, "Choose a before and now answer for every statement.")}
    end
  end

  def handle_event("submit", _params, socket) do
    {:noreply, put_flash(socket, :error, "Choose a before and now answer for every statement.")}
  end

  def handle_event(
        "select-answer",
        %{"statement-id" => statement_id, "moment" => moment, "answer" => answer},
        socket
      )
      when moment in ["before", "after"] and answer in ["for", "against", "abstain"] do
    answers =
      socket.assigns.form_params
      |> Map.get("answers", %{})
      |> Map.update(statement_id, %{moment => answer}, &Map.put(&1, moment, answer))

    {:noreply, update(socket, :form_params, &Map.put(&1, "answers", answers))}
  end

  def handle_event("toggle-delegate", %{"id" => id}, socket) do
    ids = List.wrap(socket.assigns.form_params["delegate_ids"])
    id = to_string(id)
    ids = if id in ids, do: List.delete(ids, id), else: ids ++ [id]

    {:noreply, update(socket, :form_params, &Map.put(&1, "delegate_ids", ids))}
  end

  def handle_event("select-council-list", %{"response" => %{"council_list_id" => id}}, socket) do
    {:noreply, update(socket, :form_params, &Map.put(&1, "council_list_id", id))}
  end

  def handle_event("new-person-change", %{"new_person" => person_params}, socket) do
    merged_params = Map.merge(socket.assigns.new_person_form.params, person_params)

    {:noreply,
     socket
     |> assign(:new_person_form, new_person_form(merged_params))
     |> assign(:new_person_error, nil)}
  end

  def handle_event("search-delegates", %{"delegate_search" => query}, socket) do
    results =
      if searchable?(query) do
        excluded_ids =
          creator_delegate_ids(socket) ++
            selected_extra_delegate_ids(socket) ++ current_author_ids(socket)

        Authors.list_authors(
          search: String.trim(query),
          order_by_search_relevance: query,
          limit: @search_limit
        )
        |> Authors.with_quote_counts()
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
      {:noreply, select_extra_delegate(socket, delegate)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove-extra-delegate", %{"id" => id}, socket) do
    case parse_id(id) do
      {:ok, id} ->
        form_params =
          Map.update(socket.assigns.form_params, "delegate_ids", [], fn ids ->
            Enum.reject(ids || [], &(&1 == to_string(id)))
          end)

        {:noreply,
         socket
         |> assign(:form_params, form_params)
         |> update(:selected_extra_delegates, &Enum.reject(&1, fn author -> author.id == id end))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("delegate-keydown", %{"key" => "ArrowDown"}, socket) do
    {:noreply, update_delegate_selected_index(socket, 1)}
  end

  def handle_event("delegate-keydown", %{"key" => "ArrowUp"}, socket) do
    {:noreply, update_delegate_selected_index(socket, -1)}
  end

  def handle_event("delegate-keydown", %{"key" => "Enter"}, socket) do
    case Enum.at(socket.assigns.delegate_results, socket.assigns.delegate_selected_index) do
      nil -> {:noreply, socket}
      delegate -> {:noreply, select_extra_delegate(socket, delegate)}
    end
  end

  def handle_event("delegate-keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :delegate_results, [])}
  end

  def handle_event("delegate-keydown", _params, socket), do: {:noreply, socket}

  def handle_event("toggle-new-person", _params, socket) do
    {:noreply,
     socket
     |> update(:show_new_person_form, &(!&1))
     |> assign(:new_person_error, nil)}
  end

  def handle_event("add-new-person", _params, socket) do
    params = socket.assigns.new_person_form.params

    case validate_new_person(params) do
      {:ok, person} ->
        person = Map.put(person, "key", System.unique_integer([:positive]))

        {:noreply,
         socket
         |> update(:new_people, &(&1 ++ [person]))
         |> assign(:new_person_form, new_person_form())
         |> assign(:new_person_error, nil)
         |> assign(:show_new_person_form, false)}

      {:error, message} ->
        {:noreply, assign(socket, :new_person_error, message)}
    end
  end

  def handle_event("remove-new-person", %{"key" => key}, socket) do
    case parse_id(key) do
      {:ok, key} ->
        {:noreply,
         update(socket, :new_people, &Enum.reject(&1, fn person -> person["key"] == key end))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("remove-response", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("remove-response", _params, socket) do
    case Reconsiderations.remove_response(
           socket.assigns.reconsideration,
           socket.assigns.current_user
         ) do
      {:ok, :removed} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your response and delegations have been removed.")
         |> assign_participation()}

      {:error, :not_submitted} ->
        {:noreply, assign_participation(socket)}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "We could not remove your response. Please try again.")}
    end
  end

  defp submit_or_authenticate(%{assigns: %{current_user: nil}} = socket, params) do
    payload = %{
      delegate_ids: [],
      votes: %{},
      reconsideration: %{
        slug: socket.assigns.reconsideration.slug,
        responses: params["answers"],
        council_list_id: params["council_list_id"],
        delegate_ids: params["delegate_ids"],
        new_people: new_people_payload(socket)
      }
    }

    {:noreply,
     socket
     |> assign(:form_params, params)
     |> assign(:show_auth, true)
     |> assign(:pending_actions, Jason.encode!(payload))}
  end

  defp submit_or_authenticate(socket, params) do
    case Reconsiderations.submit_response(
           socket.assigns.reconsideration,
           socket.assigns.current_user,
           params["answers"],
           params["delegate_ids"],
           params["council_list_id"],
           new_people_payload(socket)
         ) do
      {:ok, _responses} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your response and delegations have been saved.")
         |> assign(:show_auth, false)
         |> assign_participation()}

      {:error, :already_submitted} ->
        {:noreply, assign_participation(socket)}

      {:error, reason} when reason in [:invalid_answers, :incomplete_answers] ->
        {:noreply,
         socket
         |> assign(:form_params, params)
         |> put_flash(:error, "Choose a before and now answer for every statement.")}

      {:error, {:invalid_person, message}} ->
        {:noreply,
         socket
         |> assign(:form_params, params)
         |> assign(:new_person_error, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form_params, params)
         |> assign(:new_person_error, changeset_error(changeset))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:form_params, params)
         |> put_flash(:error, "We could not save your response. Please try again.")}
    end
  end

  defp assign_participation(%{assigns: %{current_user: nil}} = socket) do
    socket
    |> assign(:completed, false)
    |> assign(:show_results, false)
    |> assign(:personal_responses, %{})
    |> assign(:stats, nil)
    |> assign(:council_lists, [])
    |> assign(:existing_delegate_ids, [])
  end

  defp assign_participation(socket) do
    reconsideration = socket.assigns.reconsideration
    author_id = socket.assigns.current_user.author_id
    responses = Reconsiderations.responses_for_author(reconsideration.id, author_id)

    socket
    |> assign(:completed, responses != [])
    |> assign(:show_results, responses != [])
    |> assign(:personal_responses, Map.new(responses, &{&1.statement_id, &1}))
    |> assign(:stats, if(responses == [], do: nil, else: Reconsiderations.stats(reconsideration)))
    |> assign(:council_lists, elem(YouCongress.Councils.ensure(author_id), 1).lists)
    |> assign(:existing_delegate_ids, Delegations.delegate_ids_by_deleguee_id(author_id))
  end

  defp normalize_form_params(params, socket) do
    extra_ids = Enum.map(socket.assigns.selected_extra_delegates, &to_string(&1.id))

    %{
      "answers" => params["answers"] || %{},
      "council_list_id" => params["council_list_id"],
      "delegate_ids" => Enum.uniq(List.wrap(params["delegate_ids"]) ++ extra_ids)
    }
  end

  defp new_person_form(params \\ %{}) do
    defaults = %{"x" => "", "wikipedia_url" => "", "name" => "", "bio" => ""}
    to_form(Map.merge(defaults, params), as: :new_person)
  end

  defp validate_new_person(params) do
    person =
      Map.new(~w(x wikipedia_url name bio), fn field ->
        {field, params |> Map.get(field, "") |> String.trim()}
      end)

    x = normalize_x_for_validation(person["x"])
    wikipedia_url = person["wikipedia_url"]
    name = person["name"]
    bio = person["bio"]

    cond do
      person["x"] != "" and is_nil(x) ->
        {:error, "Enter a valid X handle or profile URL."}

      wikipedia_url != "" and not YouCongress.WikipediaUrl.valid?(wikipedia_url) ->
        {:error, "Enter a valid HTTPS Wikipedia article URL."}

      x || wikipedia_url != "" || (name != "" and bio != "") ->
        {:ok, person}

      true ->
        {:error, "Provide an X profile, a Wikipedia article, or both name and bio."}
    end
  end

  defp normalize_x_for_validation(""), do: nil

  defp normalize_x_for_validation(value) do
    username =
      value
      |> String.replace(~r{\Ahttps?://(?:www\.)?(?:x\.com|twitter\.com)/}i, "")
      |> String.trim_leading("@")
      |> String.trim_trailing("/")

    if Regex.match?(~r/\A[A-Za-z0-9_]{1,15}\z/, username), do: username
  end

  defp new_people_payload(socket) do
    Enum.map(socket.assigns.new_people, &Map.drop(&1, ["key"]))
  end

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Map.values()
    |> List.flatten()
    |> List.first()
    |> Kernel.||("Check the person's information and try again.")
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

  defp creator_delegate_ids(socket) do
    Enum.map(socket.assigns.reconsideration.delegates, & &1.author_id)
  end

  defp selected_extra_delegate_ids(socket) do
    Enum.map(socket.assigns.selected_extra_delegates, & &1.id)
  end

  defp current_author_ids(%{assigns: %{current_user: nil}}), do: []
  defp current_author_ids(socket), do: [socket.assigns.current_user.author_id]

  defp select_extra_delegate(socket, delegate) do
    ids =
      socket.assigns.form_params["delegate_ids"]
      |> List.wrap()
      |> Kernel.++([to_string(delegate.id)])
      |> Enum.uniq()

    socket
    |> update(:selected_extra_delegates, &(&1 ++ [delegate]))
    |> update(:form_params, &Map.put(&1, "delegate_ids", ids))
    |> assign(:delegate_query, "")
    |> assign(:delegate_results, [])
    |> assign(:delegate_selected_index, 0)
    |> push_event("clear-autocomplete", %{id: "reconsider-delegate-search"})
  end

  defp update_delegate_selected_index(%{assigns: %{delegate_results: []}} = socket, _change),
    do: assign(socket, :delegate_selected_index, 0)

  defp update_delegate_selected_index(socket, change) do
    next_index =
      (socket.assigns.delegate_selected_index + change)
      |> max(0)
      |> min(length(socket.assigns.delegate_results) - 1)

    assign(socket, :delegate_selected_index, next_index)
  end

  defp active_delegate_option_id(results, selected_index) do
    case Enum.at(results, selected_index) do
      nil -> nil
      delegate -> "reconsider-delegate-result-#{delegate.id}"
    end
  end

  defp complete?(params, reconsideration) do
    answers = params["answers"]

    Enum.all?(reconsideration.reconsideration_statements, fn item ->
      case answers[to_string(item.statement_id)] do
        %{"before" => before_answer, "after" => after_answer}
        when before_answer in ~w(for against abstain) and after_answer in ~w(for against abstain) ->
          true

        _ ->
          false
      end
    end)
  end

  defp selected_answer(form_params, statement_id, moment) do
    get_in(form_params, ["answers", to_string(statement_id), to_string(moment)])
  end

  defp available_delegates(reconsideration, nil), do: reconsideration.delegates

  defp available_delegates(reconsideration, current_user) do
    Enum.reject(reconsideration.delegates, &(&1.author_id == current_user.author_id))
  end

  defp already_delegating?(delegate_id, existing_ids), do: delegate_id in existing_ids

  defp changed?(%{before_answer: before_answer, after_answer: after_answer}),
    do: before_answer != after_answer

  defp answer_label(:for), do: "For"
  defp answer_label(:against), do: "Against"
  defp answer_label(:abstain), do: "Abstain"

  defp answer_classes(:for),
    do: "peer-checked:border-green-600 peer-checked:bg-green-50 peer-checked:text-green-800"

  defp answer_classes(:against),
    do: "peer-checked:border-red-600 peer-checked:bg-red-50 peer-checked:text-red-800"

  defp answer_classes(:abstain),
    do: "peer-checked:border-gray-600 peer-checked:bg-gray-100 peer-checked:text-gray-800"

  defp author_name(author), do: author.name || author.twitter_username || "YouCongress author"

  defp author_username(%{username: username}) when is_binary(username), do: "@#{username}"

  defp author_username(%{twitter_username: username}) when is_binary(username),
    do: "@#{username}"

  defp author_username(_author), do: nil

  defp new_person_name(person) do
    cond do
      person["name"] != "" -> person["name"]
      person["x"] != "" -> "@#{normalize_x_for_validation(person["x"])}"
      person["wikipedia_url"] != "" -> wikipedia_title(person["wikipedia_url"])
      true -> "New person"
    end
  end

  defp wikipedia_title(url) do
    case YouCongress.WikipediaUrl.parse(url) do
      {:ok, %{title: title}} -> String.replace(title, "_", " ")
      _ -> "Wikipedia profile"
    end
  end

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"

  defp content_label(%{content_type: :video}), do: "video"
  defp content_label(_), do: "article"

  defp creator?(%{author_id: author_id}, %{creator_id: author_id}) when not is_nil(author_id),
    do: true

  defp creator?(_current_user, _reconsideration), do: false

  defp manager?(current_user, reconsideration) do
    creator?(current_user, reconsideration) or Accounts.admin?(current_user)
  end

  defp share_instruction(%{content_type: :video}) do
    "Add this link to your video's description or pin it in a comment."
  end

  defp share_instruction(_reconsideration) do
    "Add a link or button to this page in your article."
  end

  defp youtube_embed_url(%{content_type: :video, content_url: content_url}) do
    with %URI{host: host} = uri <- URI.parse(content_url),
         host when is_binary(host) <- normalize_host(host),
         video_id when is_binary(video_id) <- youtube_video_id(uri, host),
         true <- valid_youtube_video_id?(video_id) do
      "https://www.youtube-nocookie.com/embed/#{video_id}"
    else
      _ -> nil
    end
  end

  defp youtube_embed_url(_reconsideration), do: nil

  defp normalize_host(host) do
    host
    |> String.downcase()
    |> String.trim_leading("www.")
  end

  defp youtube_video_id(uri, "youtu.be"), do: first_path_segment(uri.path)

  defp youtube_video_id(uri, host) when host in ["youtube.com", "m.youtube.com"] do
    case String.split(uri.path || "", "/", trim: true) do
      [prefix, video_id | _rest] when prefix in ["embed", "live", "shorts", "v"] ->
        video_id

      _other ->
        uri.query
        |> Kernel.||("")
        |> URI.decode_query()
        |> Map.get("v")
    end
  end

  defp youtube_video_id(_uri, _host), do: nil

  defp first_path_segment(path) do
    path
    |> Kernel.||("")
    |> String.split("/", trim: true)
    |> List.first()
  end

  defp valid_youtube_video_id?(video_id),
    do: String.match?(video_id, ~r/^[A-Za-z0-9_-]{11}$/)

  defp default_description(reconsideration) do
    "Did this #{content_label(reconsideration)} change your mind? Record your before and now positions."
  end

  defp results_toggle_path(reconsideration, true, false) do
    ~p"/@#{reconsideration.creator.username}/r/#{reconsideration.slug}"
  end

  defp results_toggle_path(reconsideration, _show_results, _completed) do
    ~p"/@#{reconsideration.creator.username}/r/#{reconsideration.slug}?results=true"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-8 sm:px-6">
      <section
        :if={@can_manage_reconsideration}
        id="reconsider-share-banner"
        aria-label="Share your Reconsider page"
        class="mb-8 flex flex-col gap-3 rounded-xl border border-indigo-200 bg-indigo-50 px-4 py-3 sm:flex-row sm:items-center"
      >
        <div class="flex-1 text-sm text-indigo-950">
          <p class="font-semibold">Share this link with your audience</p>
          <p class="mt-0.5 text-indigo-800">{share_instruction(@reconsideration)}</p>
        </div>
        <button
          type="button"
          data-copy-current-url
          data-copy-url={@return_to}
          data-copy-success-label="Link copied!"
          aria-label="Copy link to your Reconsider page"
          class="inline-flex flex-none items-center justify-center gap-1.5 rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        >
          <.icon name="hero-link" class="h-4 w-4" /> Copy link
        </button>
        <.link
          :if={!@completed}
          id="reconsider-see-results"
          patch={results_toggle_path(@reconsideration, @show_results, @completed)}
          class="inline-flex flex-none items-center justify-center rounded-md border border-indigo-300 bg-white px-3 py-2 text-sm font-semibold text-indigo-700 shadow-sm hover:bg-indigo-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        >
          {if @show_results and not @completed, do: "Hide results", else: "See results"}
        </.link>
      </section>

      <div class="mb-8 text-center">
        <p class="mb-2 text-sm font-semibold uppercase tracking-wide text-indigo-600">Reconsider</p>
        <h1 class="text-3xl font-bold tracking-tight text-gray-900">{@reconsideration.title}</h1>
        <p class="mt-3 text-gray-600">
          {@reconsideration.description || default_description(@reconsideration)}
        </p>
        <p
          :if={!@reconsideration.hide_creator_attribution}
          id="reconsider-creator-attribution"
          class="mt-2 text-sm text-gray-500"
        >
          Created on YouCongress by {author_name(@reconsideration.creator)}
        </p>
        <%= if embed_url = youtube_embed_url(@reconsideration) do %>
          <div class="mx-auto mt-6 aspect-video max-w-xl overflow-hidden rounded-xl bg-black shadow-sm">
            <iframe
              id="reconsider-youtube-video"
              class="h-full w-full"
              src={embed_url}
              title={"YouTube video: #{@reconsideration.title}"}
              loading="lazy"
              referrerpolicy="strict-origin-when-cross-origin"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
              allowfullscreen
            >
            </iframe>
          </div>
        <% else %>
          <.link
            href={@reconsideration.content_url}
            target="_blank"
            rel="noopener noreferrer"
            class="mt-5 inline-flex items-center rounded-lg border border-indigo-200 bg-indigo-50 px-4 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-100"
          >
            Open the original {content_label(@reconsideration)} ↗
          </.link>
        <% end %>
      </div>

      <%= if @show_results do %>
        <section id="reconsider-results" class="space-y-6">
          <div class="rounded-xl border border-indigo-200 bg-indigo-50 p-6 text-center">
            <p class="text-sm font-semibold uppercase tracking-wide text-indigo-700">
              Community result
            </p>
            <p class="mt-2 text-4xl font-bold text-gray-900">{@stats.changed_percent}%</p>
            <p class="mt-1 text-gray-700">
              of {@stats.total_participants} authenticated {if @stats.total_participants == 1,
                do: "participant says",
                else: "participants say"} they changed at least one position.
            </p>
            <p class="mt-3 text-xs text-gray-500">
              This is a self-reported result from a self-selected audience, not a representative poll.
            </p>
          </div>

          <div
            :for={item <- @reconsideration.reconsideration_statements}
            id={"result-#{item.statement_id}"}
            class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
          >
            <% response = @personal_responses[item.statement_id] %>
            <% statement_stat = Enum.find(@stats.statements, &(&1.statement_id == item.statement_id)) %>
            <h2 class="text-lg font-semibold text-gray-900">
              <.link
                href={~p"/p/#{item.statement.slug}"}
                class="hover:text-indigo-600 hover:underline"
              >
                {item.statement_title}
              </.link>
            </h2>

            <div class="mt-4">
              <h3 class="text-sm font-semibold text-gray-700">Community responses</h3>
              <div
                id={"community-transitions-#{item.statement_id}"}
                class="mt-2 divide-y divide-gray-100 rounded-lg border border-gray-200"
              >
                <div
                  :for={transition <- statement_stat.transitions}
                  id={
                    "transition-#{item.statement_id}-#{transition.before_answer}-#{transition.after_answer}"
                  }
                  class="flex flex-wrap items-center gap-2 px-3 py-2 text-sm"
                >
                  <span>{answer_label(transition.before_answer)}</span>
                  <span class="text-gray-400" aria-hidden="true">→</span>
                  <span class="font-semibold text-gray-900">
                    {answer_label(transition.after_answer)}
                  </span>
                  <span class="ml-auto text-gray-600">
                    {transition.count} {if transition.count == 1, do: "response", else: "responses"} ({transition.percent}%)
                  </span>
                </div>
              </div>
            </div>

            <div class="mt-4">
              <div class="mb-1 flex justify-between text-xs text-gray-500">
                <span>{statement_stat.changed_percent}% reported changing</span>
                <span>{statement_stat.total} completed</span>
              </div>
              <div class="h-2 overflow-hidden rounded-full bg-gray-100">
                <div class={[
                  "h-full rounded-full bg-indigo-600",
                  percentage_width_class(statement_stat.changed_percent)
                ]}>
                </div>
              </div>
            </div>

            <div
              :if={response}
              id={"your-response-#{item.statement_id}"}
              class="mt-5 rounded-lg border border-gray-200 bg-gray-50 p-3"
            >
              <p class="text-xs font-semibold uppercase tracking-wide text-gray-500">Your response</p>
              <div class="mt-2 flex flex-wrap items-center gap-2 text-sm">
                <span class="rounded-full bg-white px-3 py-1 ring-1 ring-inset ring-gray-200">
                  Before: {answer_label(response.before_answer)}
                </span>
                <span aria-hidden="true">→</span>
                <span class="rounded-full bg-indigo-100 px-3 py-1 font-semibold text-indigo-800">
                  Now: {answer_label(response.after_answer)}
                </span>
                <span class={[
                  "ml-auto rounded-full px-3 py-1 font-semibold",
                  changed?(response) && "bg-amber-100 text-amber-800",
                  !changed?(response) && "bg-gray-200 text-gray-600"
                ]}>
                  {if changed?(response), do: "Changed", else: "Unchanged"}
                </span>
              </div>
            </div>
          </div>

          <div
            :if={@stats.delegates != []}
            id="delegation-results"
            class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
          >
            <h2 class="text-lg font-semibold text-gray-900">Delegations chosen</h2>
            <p class="mt-1 text-sm text-gray-600">
              How many participants chose each person through this Reconsider page.
            </p>
            <div class="mt-4 divide-y divide-gray-100 rounded-lg border border-gray-200">
              <div
                :for={delegate <- @stats.delegates}
                id={"delegate-result-#{delegate.author_id}"}
                class="flex items-center gap-3 px-3 py-3"
              >
                <.link
                  href={SEO.author_path(delegate.author)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex min-w-0 items-center gap-3 hover:text-indigo-600"
                >
                  <.profile_avatar
                    name={delegate.author.name}
                    image_url={delegate.author.profile_image_url}
                    class="h-9 w-9 text-sm"
                  />
                  <span class="truncate font-medium">
                    {author_name(delegate.author)}
                    <span class="font-normal text-gray-500">
                      ({delegate.author.quotes_count} {plural(delegate.author.quotes_count, "quote")})
                    </span>
                  </span>
                </.link>
                <span class="ml-auto text-sm text-gray-600">
                  {delegate.count} {if delegate.count == 1, do: "participant", else: "participants"} ({delegate.percent}%)
                </span>
              </div>
            </div>
          </div>

          <div :if={@completed} id="reconsider-response-actions" class="pt-2 text-center">
            <button
              id="remove-reconsider-response"
              type="button"
              phx-click="remove-response"
              data-confirm="Remove your response and delegations? This will also remove your current votes on these statements."
              class="text-sm font-semibold text-red-700 hover:text-red-600 hover:underline"
            >
              Remove my response and delegations
            </button>
          </div>
        </section>
      <% else %>
        <form id="reconsider-form" phx-submit="submit" class="space-y-6">
          <div class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
            <h2 class="text-xl font-semibold text-gray-900">Did this change your mind?</h2>
            <p class="mt-2 text-sm text-gray-600">
              For each statement, tell us what you thought before and what you think now.
            </p>
          </div>

          <fieldset
            :for={{item, index} <- Enum.with_index(@reconsideration.reconsideration_statements, 1)}
            id={"statement-#{item.statement_id}"}
            class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
          >
            <legend class="px-1 text-base font-semibold text-gray-900">
              {index}. {item.statement_title}
            </legend>

            <div class="mt-4 grid gap-5 md:grid-cols-2">
              <div>
                <p class="mb-2 text-sm font-semibold text-gray-700">
                  Before this {content_label(@reconsideration)}
                </p>
                <div class="grid grid-cols-3 gap-2">
                  <label :for={answer <- @answers} class="cursor-pointer">
                    <input
                      class="peer sr-only"
                      type="radio"
                      name={"response[answers][#{item.statement_id}][before]"}
                      value={answer}
                      phx-click="select-answer"
                      phx-value-statement-id={item.statement_id}
                      phx-value-moment="before"
                      phx-value-answer={answer}
                      checked={
                        selected_answer(@form_params, item.statement_id, :before) == to_string(answer)
                      }
                      required
                    />
                    <span class={[
                      "block rounded-lg border border-gray-200 px-2 py-2 text-center text-sm font-medium hover:bg-gray-50",
                      answer_classes(answer)
                    ]}>
                      {answer_label(answer)}
                    </span>
                  </label>
                </div>
              </div>

              <div>
                <p class="mb-2 text-sm font-semibold text-gray-700">Now</p>
                <div class="grid grid-cols-3 gap-2">
                  <label :for={answer <- @answers} class="cursor-pointer">
                    <input
                      class="peer sr-only"
                      type="radio"
                      name={"response[answers][#{item.statement_id}][after]"}
                      value={answer}
                      phx-click="select-answer"
                      phx-value-statement-id={item.statement_id}
                      phx-value-moment="after"
                      phx-value-answer={answer}
                      checked={
                        selected_answer(@form_params, item.statement_id, :after) == to_string(answer)
                      }
                      required
                    />
                    <span class={[
                      "block rounded-lg border border-gray-200 px-2 py-2 text-center text-sm font-medium hover:bg-gray-50",
                      answer_classes(answer)
                    ]}>
                      {answer_label(answer)}
                    </span>
                  </label>
                </div>
              </div>
            </div>
          </fieldset>

          <fieldset
            id="reconsider-delegates"
            class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
          >
            <legend class="px-1 text-base font-semibold text-gray-900">
              Who would you trust to represent you?
            </legend>
            <p class="mt-2 text-sm text-gray-600">
              Optional. When you have not voted directly on an issue, the first council list with more
              For than Against determines delegation. Your own votes always take priority. Your
              selections also help identify the most trusted people.
            </p>

            <div
              :if={available_delegates(@reconsideration, @current_user) != []}
              id="suggested-delegates"
              class="mt-4 space-y-3"
            >
              <div
                :for={delegate <- available_delegates(@reconsideration, @current_user)}
                class="flex items-center gap-3 rounded-lg border border-gray-200 p-3"
              >
                <input
                  id={"suggested-delegate-#{delegate.author_id}"}
                  type="checkbox"
                  name="response[delegate_ids][]"
                  value={delegate.author_id}
                  phx-click="toggle-delegate"
                  phx-value-id={delegate.author_id}
                  checked={to_string(delegate.author_id) in @form_params["delegate_ids"]}
                  class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                />
                <label for={"suggested-delegate-#{delegate.author_id}"} class="cursor-pointer">
                  <.profile_avatar
                    name={delegate.author.name}
                    image_url={delegate.author.profile_image_url}
                    class="h-9 w-9 text-sm"
                  />
                </label>
                <div class="min-w-0 flex-1">
                  <div
                    id={"suggested-delegate-name-row-#{delegate.author_id}"}
                    class="flex min-w-0 items-baseline gap-1"
                  >
                    <label
                      for={"suggested-delegate-#{delegate.author_id}"}
                      class="min-w-0 cursor-pointer truncate font-medium text-gray-900 hover:text-indigo-600"
                    >
                      {author_name(delegate.author)}
                    </label>
                    <.link
                      id={"delegate-quotes-#{delegate.author_id}"}
                      href={SEO.author_path(delegate.author)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="shrink-0 text-sm text-gray-500 underline hover:text-indigo-600"
                    >
                      ({delegate.author.quotes_count} {plural(delegate.author.quotes_count, "quote")})
                    </.link>
                  </div>
                  <p
                    :if={delegate.author.bio}
                    id={"suggested-delegate-bio-#{delegate.author_id}"}
                    class="truncate text-xs text-gray-500"
                  >
                    {delegate.author.bio}
                  </p>
                </div>
                <span
                  :if={already_delegating?(delegate.author_id, @existing_delegate_ids)}
                  class="shrink-0 text-xs font-medium text-green-700"
                >
                  Already a delegate
                </span>
              </div>
            </div>

            <div
              :if={@selected_extra_delegates != []}
              id="selected-extra-delegates"
              class="mt-4 space-y-2"
            >
              <p class="text-sm font-semibold text-gray-700">People you added</p>
              <div
                :for={delegate <- @selected_extra_delegates}
                id={"selected-extra-delegate-#{delegate.id}"}
                class="flex items-center gap-3 rounded-lg border border-indigo-200 bg-indigo-50 p-3"
              >
                <input type="hidden" name="response[delegate_ids][]" value={delegate.id} />
                <.profile_avatar
                  name={delegate.name}
                  image_url={delegate.profile_image_url}
                  class="h-9 w-9 text-sm"
                />
                <div class="min-w-0 flex-1">
                  <div
                    id={"selected-delegate-name-row-#{delegate.id}"}
                    class="flex min-w-0 items-baseline gap-1"
                  >
                    <.link
                      href={SEO.author_path(delegate)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="min-w-0 truncate text-sm font-medium text-gray-900 hover:text-indigo-600"
                    >
                      {author_name(delegate)}
                    </.link>
                    <.link
                      id={"selected-delegate-quotes-#{delegate.id}"}
                      href={SEO.author_path(delegate)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="shrink-0 text-sm text-gray-500 underline hover:text-indigo-600"
                    >
                      ({delegate.quotes_count} {plural(delegate.quotes_count, "quote")})
                    </.link>
                  </div>
                  <p
                    :if={delegate.bio}
                    id={"selected-delegate-bio-#{delegate.id}"}
                    class="truncate text-xs text-gray-500"
                  >
                    {delegate.bio}
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="remove-extra-delegate"
                  phx-value-id={delegate.id}
                  aria-label={"Remove #{author_name(delegate)}"}
                  class="text-xl leading-5 text-indigo-700 hover:text-indigo-900"
                >
                  ×
                </button>
              </div>
            </div>

            <div :if={@new_people != []} id="selected-new-people" class="mt-4 space-y-2">
              <p class="text-sm font-semibold text-gray-700">New people you added</p>
              <div
                :for={person <- @new_people}
                id={"selected-new-person-#{person["key"]}"}
                class="flex items-start gap-3 rounded-lg border border-indigo-200 bg-indigo-50 p-3"
              >
                <div class="min-w-0 flex-1">
                  <span class="block truncate text-sm font-medium text-gray-900">
                    {new_person_name(person)}
                  </span>
                  <span
                    :if={person["bio"] != ""}
                    class="mt-0.5 line-clamp-2 block text-xs text-gray-500"
                  >
                    {person["bio"]}
                  </span>
                  <span class="block text-xs text-indigo-700">
                    {if @current_user,
                      do: "Profile will be created when you save your response.",
                      else: "Profile will be created after sign-in."}
                  </span>
                </div>
                <button
                  type="button"
                  phx-click="remove-new-person"
                  phx-value-key={person["key"]}
                  aria-label={"Remove #{new_person_name(person)}"}
                  class="text-xl leading-5 text-indigo-700 hover:text-indigo-900"
                >
                  ×
                </button>
              </div>
            </div>

            <div id="reconsider-delegate-picker" class="mt-5 space-y-2">
              <label
                for="reconsider-delegate-search"
                class="block text-sm font-semibold text-gray-700"
              >
                Search anyone on YouCongress
              </label>
              <div class="relative">
                <input
                  id="reconsider-delegate-search"
                  name="delegate_search"
                  type="search"
                  value={@delegate_query}
                  placeholder="Search by name, username, or bio…"
                  autocomplete="off"
                  role="combobox"
                  aria-autocomplete="list"
                  aria-controls="reconsider-delegate-results"
                  aria-expanded={to_string(@delegate_results != [])}
                  aria-activedescendant={
                    active_delegate_option_id(@delegate_results, @delegate_selected_index)
                  }
                  phx-change="search-delegates"
                  phx-keydown="delegate-keydown"
                  phx-debounce="250"
                  onkeydown="if(['ArrowDown','ArrowUp','Enter','Escape'].includes(event.key)) event.preventDefault()"
                  class="block w-full rounded-lg border-0 px-3 py-2 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm"
                />

                <div
                  :if={@delegate_results != []}
                  id="reconsider-delegate-results"
                  role="listbox"
                  class="absolute z-20 mt-1 max-h-72 w-full overflow-y-auto rounded-lg border border-gray-200 bg-white p-1 shadow-lg"
                >
                  <button
                    :for={{delegate, index} <- Enum.with_index(@delegate_results)}
                    id={"reconsider-delegate-result-#{delegate.id}"}
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
                id="no-reconsider-delegate-results"
                class="text-xs text-gray-500"
              >
                No matching people found. You can add a new person below.
              </p>
            </div>

            <div id="new-reconsider-person" class="mt-5 border-t border-gray-200 pt-4">
              <button
                type="button"
                phx-click="toggle-new-person"
                aria-expanded={to_string(@show_new_person_form)}
                class="text-sm font-semibold text-indigo-700 hover:text-indigo-600"
              >
                {if @show_new_person_form,
                  do: "Cancel adding a new person",
                  else: "Can’t find someone? Add them"}
              </button>

              <div :if={@show_new_person_form} class="mt-4 space-y-3 rounded-lg bg-gray-50 p-4">
                <p class="text-xs text-gray-600">
                  Provide an X profile, a Wikipedia article, or both a name and bio.
                </p>
                <.input
                  field={@new_person_form[:x]}
                  type="text"
                  label="X handle or profile URL"
                  placeholder="@username or https://x.com/username"
                  phx-change="new-person-change"
                />
                <.input
                  field={@new_person_form[:wikipedia_url]}
                  type="url"
                  label="Wikipedia article URL"
                  placeholder="https://en.wikipedia.org/wiki/..."
                  phx-change="new-person-change"
                />
                <.input
                  field={@new_person_form[:name]}
                  type="text"
                  label="Name"
                  phx-change="new-person-change"
                />
                <.input
                  field={@new_person_form[:bio]}
                  type="text"
                  label="One-line biography"
                  phx-change="new-person-change"
                />
                <p :if={@new_person_error} id="new-person-error" class="text-sm text-red-700">
                  {@new_person_error}
                </p>
                <button
                  type="button"
                  phx-click="add-new-person"
                  class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white hover:bg-indigo-500"
                >
                  Add this person
                </button>
              </div>
              <p
                :if={@new_person_error && !@show_new_person_form}
                id="new-person-error"
                class="mt-2 text-sm text-red-700"
              >
                {@new_person_error}
              </p>
            </div>

            <div :if={@council_lists != []} id="delegate-council-list" class="mt-5">
              <label>
                Council list for these selections
                <select
                  name="response[council_list_id]"
                  phx-change="select-council-list"
                  class="block rounded border-gray-300"
                >
                  <option
                    :for={list <- @council_lists}
                    value={list.id}
                    selected={
                      to_string(list.id) == @form_params["council_list_id"] or
                        (is_nil(@form_params["council_list_id"]) and list.fallback)
                    }
                  >
                    {list.name}{if list.fallback, do: " (final fallback)"}
                  </option>
                </select>
              </label>
              <.link href={~p"/council"} class="text-sm text-indigo-700">
                Build or compare your council
              </.link>
            </div>
          </fieldset>

          <div
            :if={@show_auth}
            id="reconsider-auth"
            class="rounded-xl border border-indigo-200 bg-indigo-50 p-5"
          >
            <h2 class="text-lg font-semibold text-gray-900">Sign in to record your response</h2>
            <p class="mt-2 text-sm text-gray-600">
              Authentication protects the results from duplicate responses. We will not post anything
              to your account.
            </p>
            <LoginButtons.render
              class="mt-4"
              pending_actions={@pending_actions}
              return_to={@return_to}
              email_action={:sign_up}
            />
          </div>

          <button
            type="submit"
            class="w-full rounded-lg bg-indigo-600 px-5 py-3 text-base font-semibold text-white shadow-sm hover:bg-indigo-500"
          >
            {if @current_user,
              do: "Save my response",
              else: "Record my response and see results"}
          </button>

          <p class="text-center text-xs text-gray-500">
            Only authenticated, completed responses are included in the results.
          </p>
        </form>
      <% end %>
    </div>
    """
  end
end
