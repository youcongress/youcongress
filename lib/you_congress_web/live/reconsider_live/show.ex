defmodule YouCongressWeb.ReconsiderLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Delegations
  alias YouCongress.Reconsiderations
  alias YouCongressWeb.Components.LoginButtons
  alias YouCongressWeb.SEO

  @answers [:for, :abstain, :against]

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
      |> assign(:return_to, return_to)
      |> assign(:answers, @answers)
      |> assign(:form_params, %{"answers" => %{}, "delegate_ids" => []})
      |> assign(:show_auth, false)
      |> assign(:pending_actions, nil)
      |> assign(:page_title, reconsideration.title)
      |> assign(
        :page_description,
        reconsideration.description || default_description(reconsideration)
      )
      |> assign_participation()

    {:ok, socket}
  end

  @impl true
  def handle_event("submit", %{"response" => params}, socket) do
    params = normalize_form_params(params)

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

  defp submit_or_authenticate(%{assigns: %{current_user: nil}} = socket, params) do
    payload = %{
      delegate_ids: [],
      votes: %{},
      reconsideration: %{
        slug: socket.assigns.reconsideration.slug,
        responses: params["answers"],
        delegate_ids: params["delegate_ids"]
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
           params["delegate_ids"]
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
    |> assign(:personal_responses, %{})
    |> assign(:stats, nil)
    |> assign(:existing_delegate_ids, [])
  end

  defp assign_participation(socket) do
    reconsideration = socket.assigns.reconsideration
    author_id = socket.assigns.current_user.author_id
    responses = Reconsiderations.responses_for_author(reconsideration.id, author_id)

    socket
    |> assign(:completed, responses != [])
    |> assign(:personal_responses, Map.new(responses, &{&1.statement_id, &1}))
    |> assign(:stats, if(responses == [], do: nil, else: Reconsiderations.stats(reconsideration)))
    |> assign(:existing_delegate_ids, Delegations.delegate_ids_by_deleguee_id(author_id))
  end

  defp normalize_form_params(params) do
    %{
      "answers" => params["answers"] || %{},
      "delegate_ids" => List.wrap(params["delegate_ids"])
    }
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

  defp content_label(%{content_type: :video}), do: "video"
  defp content_label(_), do: "article"

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-8 sm:px-6">
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

      <%= if @completed do %>
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
                <div
                  class="h-full rounded-full bg-indigo-600"
                  style={"width: #{statement_stat.changed_percent}%"}
                >
                </div>
              </div>
            </div>

            <div
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
                  class="flex min-w-0 items-center gap-3 hover:text-indigo-600"
                >
                  <img
                    :if={delegate.author.profile_image_url}
                    src={delegate.author.profile_image_url}
                    alt=""
                    class="h-9 w-9 rounded-full"
                  />
                  <span class="truncate font-medium">{author_name(delegate.author)}</span>
                </.link>
                <span class="ml-auto text-sm text-gray-600">
                  {delegate.count} {if delegate.count == 1, do: "participant", else: "participants"} ({delegate.percent}%)
                </span>
              </div>
            </div>
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
            :if={available_delegates(@reconsideration, @current_user) != []}
            class="rounded-xl border border-gray-200 bg-white p-5 shadow-sm"
          >
            <legend class="px-1 text-base font-semibold text-gray-900">
              Who would you trust to represent you?
            </legend>
            <p class="mt-2 text-sm text-gray-600">
              Optional. These are global delegations. When you have not voted directly on an issue,
              YouCongress follows the most common answer among your delegates. Your own votes always
              take priority.
            </p>

            <div class="mt-4 space-y-3">
              <label
                :for={delegate <- available_delegates(@reconsideration, @current_user)}
                class="flex items-center gap-3 rounded-lg border border-gray-200 p-3"
              >
                <input
                  type="checkbox"
                  name="response[delegate_ids][]"
                  value={delegate.author_id}
                  checked={
                    already_delegating?(delegate.author_id, @existing_delegate_ids) ||
                      to_string(delegate.author_id) in @form_params["delegate_ids"]
                  }
                  disabled={already_delegating?(delegate.author_id, @existing_delegate_ids)}
                  class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                />
                <img
                  :if={delegate.author.profile_image_url}
                  src={delegate.author.profile_image_url}
                  alt=""
                  class="h-9 w-9 rounded-full"
                />
                <span class="font-medium text-gray-900">{author_name(delegate.author)}</span>
                <span
                  :if={already_delegating?(delegate.author_id, @existing_delegate_ids)}
                  class="ml-auto text-xs font-medium text-green-700"
                >
                  Already a delegate
                </span>
              </label>
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
            {if @current_user, do: "Save my response", else: "Record my response"}
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
