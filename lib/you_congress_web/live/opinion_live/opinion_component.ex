defmodule YouCongressWeb.OpinionLive.OpinionComponent do
  use YouCongressWeb, :live_component

  use Phoenix.VerifiedRoutes, endpoint: YouCongressWeb.Endpoint, router: YouCongressWeb.Router

  alias YouCongressWeb.AuthorLive
  alias YouCongressWeb.VotingLive.VoteComponent.AiQuoteMenu
  alias YouCongressWeb.Tools.Tooltip
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongress.Likes
  alias YouCongress.Delegations
  alias YouCongressWeb.Tools.TimeAgo

  @max_x_length 280
  @url_length String.length("youcongress.com/p/should-tech-")

  def update(assigns, socket) do
    %{
      current_user: current_user,
      voting: voting,
      opinion: opinion,
      page: page
    } = assigns

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:delegating, assigns[:delegating] || false)
      |> assign(:voting, voting)
      |> assign(:opinable, assigns[:opinable] || false)
      |> assign(:delegable, assigns[:delegable] || false)
      |> assign(:opinion, opinion)
      |> assign(:liked, assigns[:liked] || false)
      |> assign(:page, page)

    {:ok, socket}
  end

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to like."})
    {:noreply, socket}
  end

  def handle_event("like", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.like(opinion_id, current_user) do
      {:ok, _} ->
        opinion =
          opinion
          |> Map.put(:likes_count, opinion.likes_count + 1)
          |> Map.put(:descendants_count, opinion.descendants_count + 1)

        socket =
          socket
          |> assign(:opinion, opinion)
          |> assign(:liked, true)

        {:noreply, socket}

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to like opinion."})
        {:noreply, socket}
    end
  end

  def handle_event("unlike", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket

    opinion_id = String.to_integer(opinion_id)

    case Likes.unlike(opinion_id, current_user) do
      {:ok, _} ->
        opinion =
          opinion
          |> Map.put(:likes_count, opinion.likes_count - 1)
          |> Map.put(:descendants_count, opinion.descendants_count - 1)

        socket =
          socket
          |> assign(:opinion, opinion)
          |> assign(:liked, false)

        {:noreply, socket}

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to unlike opinion."})
        {:noreply, socket}
    end
  end

  def handle_event("add-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    send(
      self(),
      {:put_flash, :warning, "Log in to unlock delegate voting."}
    )

    {:noreply, socket}
  end

  def handle_event("add-delegation", %{"author_id" => delegate_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        {:noreply, assign(socket, :delegating, true)}

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to add delegation."})
        {:noreply, socket}
    end
  end

  def handle_event("remove-delegation", %{"author_id" => delegate_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.delete_delegation(current_user, delegate_id) do
      {:ok, _} ->
        {:noreply, assign(socket, :delegating, false)}

      {:error, _} ->
        send(self(), {:put_flash, :error, "Failed to remove delegation."})
        {:noreply, socket}
    end
  end

  attr :opinion, :map, required: true

  def comment_icon(assigns) do
    ~H"""
    <.link href={~p"/comments/#{@opinion.id}"}>
      <img
        src="/images/comment.svg"
        alt="Comment"
        class="h-5 w-5 inline"
        cache-control="public, max-age=2592000"
      />
      <span class="text-gray-600 pl-1 text-xs">
        <%= if @opinion.descendants_count > 0, do: @opinion.descendants_count %>
      </span>
    </.link>
    """
  end

  attr :opinion, :map, required: true
  attr :liked, :boolean, default: false
  attr :target, :string, default: nil

  def like_icon(assigns) do
    ~H"""
    <img
      phx-click={if @liked, do: "unlike", else: "like"}
      phx-value-opinion_id={@opinion.id}
      phx-target={@target}
      src={"/images/#{if @liked, do: "filled-heart", else: "heart"}.svg"}
      alt="Comment"
      class="h-5 w-5 inline cursor-pointer"
      cache-control="public, max-age=2592000"
    />
    <span class="text-gray-600 pl-1 text-xs">
      <%= if @opinion.likes_count > 0, do: @opinion.likes_count %>
    </span>
    """
  end

  attr :opinion, :map, required: true
  attr :voting, :map, required: true
  attr :author, :map, required: true
  attr :current_user, :map, default: nil

  def x_icon(assigns) do
    assigns =
      assign(
        assigns,
        :href,
        x_url(
          assigns.opinion,
          assigns.voting,
          assigns.author,
          assigns.current_user
        )
      )

    ~H"""
    <a href={@href} target="_blank">
      <img
        src="/images/x.svg"
        alt="X"
        class="h-5 w-5 inline cursor-pointer"
        cache-control="public, max-age=2592000"
      />
    </a>
    """
  end

  attr :is_human, :boolean, default: true

  def avatar_icon(assigns) do
    ~H"""
    <%= if @is_human do %>
      <img
        src="/images/human-avatar.svg"
        alt="human-avatar"
        class="h-8 w-8 inline"
        cache-control="public, max-age=2592000"
      />
    <% else %>
      <img
        src="/images/robot-avatar.svg"
        alt="robot-avatar"
        class="h-8 w-8 inline"
        cache-control="public, max-age=2592000"
      />
    <% end %>
    """
  end

  defp x_url(opinion, voting, author, current_user) do
    url = " https://youcongress.com#{x_path(voting)}"

    opinion
    |> x_post(voting, author, current_user)
    |> maybe_shorten()
    |> then(&"#{&1}#{url}")
    |> URI.encode_www_form()
    |> then(&"https://x.com/intent/tweet?text=#{&1}")
  end

  def x_path(voting) do
    ~p"/p/#{voting.slug}"
  end

  defp x_post(opinion, voting, %{id: id} = _author, %{id: id} = _current_user) do
    "#{voting.title} My take: #{opinion.content}"
  end

  defp x_post(opinion, voting, author, _current_user) do
    "#{voting.title} #{print_author(author, opinion.twin)}: #{opinion.content}'"
  end

  defp maybe_shorten(text) do
    if String.length(text) > @max_x_length - @url_length do
      String.slice(text, 0..(@max_x_length - 1 - @url_length)) <> "..."
    else
      text
    end
  end

  defp print_author(author, true) do
    "#{x_username(author) || author.name}'s AI digital twin"
  end

  defp print_author(author, false) do
    x_username(author) || author.name
  end

  defp x_username(%{twitter_username: nil}), do: nil

  defp x_username(%{twitter_username: username}) do
    "@#{username}"
  end
end
