defmodule YouCongressWeb.ManifestLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Manifests

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    {:ok, socket}
  end

  alias YouCongress.Votes
  alias YouCongressWeb.VotingLive.ResultsComponent

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    manifest = Manifests.get_manifest_by_slug!(slug)

    socket =
      socket
      |> assign(:manifest, manifest)
      |> assign(:page_title, manifest.title)
      |> assign_signatures_data(manifest)
      |> assign_voting_data(manifest)

    {:noreply, socket}
  end

  alias YouCongress.Votes.VoteFrequencies

  defp assign_voting_data(socket, manifest) do
    current_user = socket.assigns.current_user

    voting_data =
      Enum.reduce(manifest.sections, %{}, fn section, acc ->
        if section.voting_id do
           frequencies = VoteFrequencies.get(section.voting_id)
           total_votes = Votes.count_by_voting(section.voting_id)

           user_vote =
             if current_user do
               Votes.get_current_user_vote(section.voting_id, current_user.author_id)
             end

           Map.put(acc, section.voting_id, %{
             frequencies: frequencies,
             total_votes: total_votes,
             user_vote: user_vote
           })
        else
          acc
        end
      end)

    assign(socket, :voting_data, voting_data)
  end

  defp assign_signatures_data(socket, manifest) do
    current_user = socket.assigns.current_user

    signed? = if current_user, do: Manifests.signed?(manifest, current_user), else: false
    count = Manifests.signatures_count(manifest)

    socket
    |> assign(:signed?, signed?)
    |> assign(:signatures_count, count)
  end

  @impl true
  def handle_event("vote", %{"voting_id" => voting_id, "answer" => answer}, socket) do
    user = socket.assigns.current_user
    voting_id = String.to_integer(voting_id)

    if user do
      vote_params = %{
        voting_id: voting_id,
        author_id: user.author_id,
        answer: String.to_atom(answer),
        direct: true
      }

      case Votes.create_or_update(vote_params) do
        {:ok, _vote} ->
          # Refresh data
          socket = assign_voting_data(socket, socket.assigns.manifest)
          {:noreply, put_flash(socket, :info, "Vote recorded")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not vote")}
      end
    else
      {:noreply, redirect(socket, to: ~p"/log_in")}
    end
  end

  @impl true
  def handle_event("clear_vote", %{"voting_id" => voting_id}, socket) do
    user = socket.assigns.current_user
    voting_id = String.to_integer(voting_id)

    if user do
      Votes.delete_vote(%{voting_id: voting_id, author_id: user.author_id})

      # Refresh data
      socket = assign_voting_data(socket, socket.assigns.manifest)
      {:noreply, put_flash(socket, :info, "Vote removed")}
    else
      {:noreply, redirect(socket, to: ~p"/log_in")}
    end
  end

  @impl true
  def handle_event("unsign", _, socket) do
    user = socket.assigns.current_user
    manifest = socket.assigns.manifest

    if user do
      case Manifests.unsign_manifest(manifest, user) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "You have removed your signature from the manifest. You can manually change your vote on the motions.")
           |> assign_signatures_data(manifest)
           |> assign_voting_data(manifest)}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not unsign manifest.")}
      end
    else
      {:noreply, redirect(socket, to: ~p"/log_in")}
    end
  end

  @impl true
  def handle_event("sign", _, socket) do
    user = socket.assigns.current_user
    manifest = socket.assigns.manifest

    if user do
      case Manifests.sign_manifest(manifest, user) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "You have successfully signed the manifest.")
           |> assign_signatures_data(manifest)
           |> assign_voting_data(manifest)}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not sign manifest.")}
      end
    else
      {:noreply, redirect(socket, to: ~p"/log_in")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-12 px-4 sm:px-6 lg:px-8 font-serif">
      <div class="max-w-3xl mx-auto bg-white shadow-xl rounded-lg overflow-hidden">

        <!-- Header -->
        <div class="bg-slate-900 px-8 py-10 text-center text-white relative overflow-hidden">
          <div class="absolute inset-0 opacity-10 bg-[url('/images/noise.png')]"></div>
          <h1 class="text-4xl md:text-5xl font-bold tracking-tight relative z-10 mb-2 font-sans">
            <%= @manifest.title %>
          </h1>
          <p class="text-slate-300 italic relative z-10 uppercase tracking-widest text-sm">
            Manifesto
          </p>
          <div :if={@manifest.user} class="mt-4 relative z-10">
            <span class="text-slate-400 text-sm font-sans">Created by <%= @manifest.user.email %></span>
            <%= if @current_user && @current_user.id == @manifest.user_id do %>
              <.link navigate={~p"/manifests/#{@manifest.slug}/edit"} class="ml-2 text-indigo-400 hover:text-indigo-300 text-sm font-sans underline">
                Edit
              </.link>
            <% end %>
          </div>
        </div>

        <!-- Body -->
        <div class="px-8 py-10 space-y-8 text-lg text-gray-800 leading-relaxed">
          <div :for={section <- @manifest.sections} class="prose prose-lg max-w-none">
            <p>
              <%= section.body %>
            </p>

            <div :if={section.voting} class="mt-6 p-6 bg-gray-50 border border-gray-200 rounded-lg not-prose font-sans">
              <div class="flex flex-col md:flex-row md:items-center justify-between mb-4">
                <div>
                   <p class="text-xs text-indigo-500 uppercase font-bold tracking-wider mb-1">
                    Linked Motion
                  </p>
                  <h3 class="font-bold text-gray-900 text-lg leading-tight">
                    <.link navigate={~p"/p/#{section.voting.slug}"} class="hover:underline hover:text-indigo-700 transition">
                      <%= section.voting.title %> &rarr;
                    </.link>
                  </h3>
                </div>
              </div>

              <% data = @voting_data[section.voting_id] %>

              <div class="mt-4">
                <ResultsComponent.horizontal_bar
                  total_votes={data.total_votes}
                  vote_frequencies={data.frequencies}
                />

                <div class="mt-6 flex flex-wrap gap-3">
                  <.vote_button
                    label="For"
                    value="for"
                    color="green"
                    voting_id={section.voting_id}
                    current_vote={data.user_vote}
                  />
                  <.vote_button
                    label="Abstain"
                    value="abstain"
                    color="blue"
                    voting_id={section.voting_id}
                    current_vote={data.user_vote}
                  />
                   <.vote_button
                    label="Against"
                    value="against"
                    color="red"
                    voting_id={section.voting_id}
                    current_vote={data.user_vote}
                  />

                  <button
                    :if={data.user_vote}
                    phx-click="clear_vote"
                    phx-value-voting_id={section.voting_id}
                    class="ml-2 text-xs text-gray-500 underline hover:text-gray-700 self-center"
                  >
                    clear
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Signatures & Action -->
        <div class="bg-gray-100 px-8 py-8 border-t border-gray-200 mt-12">
          <div class="flex flex-col items-center justify-center space-y-4">

            <div class="text-center mb-4">
              <p class="text-3xl font-bold text-indigo-600 font-sans"><%= @signatures_count %></p>
              <p class="text-gray-500 text-sm uppercase tracking-wide font-sans">Signatures</p>
            </div>

            <%= if @signed? do %>
              <div class="flex items-center space-x-2 text-green-700 bg-green-100 px-6 py-3 rounded-full font-sans font-medium">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                <span>You have signed this manifest</span>
                <button phx-click="unsign" class="ml-4 bg-red-600 hover:bg-red-700 text-white font-bold py-1 px-3 rounded">Unsign</button>
              </div>
            <% else %>
              <%= if @current_user do %>
                <button phx-click="sign" phx-disable-with="Signing..." class="font-sans bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-4 px-10 rounded-full shadow-lg transform transition hover:-translate-y-0.5 focus:outline-none focus:ring-4 focus:ring-indigo-300 text-xl">
                  Sign Manifest
                </button>
                <p class="text-sm text-gray-500 mt-2 text-center max-w-md">
                  By signing, you automatically vote <strong>For</strong> on all associated motions (unless you have already voted).
                </p>
              <% else %>
                <.link navigate={~p"/log_in"} class="font-sans bg-gray-800 hover:bg-gray-900 text-white font-bold py-3 px-8 rounded-full shadow transition">
                  Log in to Sign
                </.link>
              <% end %>
            <% end %>

          </div>
        </div>

      </div>
    </div>
    """
  end

  def vote_button(assigns) do
    # Determine if this button represents the current user's vote
    vote_val = if assigns.current_vote, do: Atom.to_string(assigns.current_vote.answer), else: nil
    active? = vote_val == assigns.value
    assigns = assign(assigns, :active?, active?)

    # Define color classes mapping
    color_classes = %{
      "red" => "bg-red-100 text-red-700 border-red-300 ring-red-500",
      "green" => "bg-green-100 text-green-700 border-green-300 ring-green-500",
      "blue" => "bg-blue-100 text-blue-700 border-blue-300 ring-blue-500"
    }

    active_color = Map.get(color_classes, assigns.color, "bg-gray-100 text-gray-700 border-gray-300 ring-gray-500")

    color_class = if assigns.active?, do: active_color, else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <button
      phx-click="vote"
      phx-value-voting_id={@voting_id}
      phx-value-answer={@value}
      class={["px-4 py-2 rounded-md text-sm font-bold transition border", @color_class]}
    >
      <%= @label %>
    </button>
    """
  end
end
