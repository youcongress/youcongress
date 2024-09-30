defmodule YouCongressWeb.OpinionLive.OpinionComponent do
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: YouCongressWeb.Endpoint, router: YouCongressWeb.Router

  alias YouCongressWeb.AuthorLive
  alias YouCongressWeb.VotingLive.VoteComponent.AiQuoteMenu
  alias YouCongressWeb.Tools.Tooltip
  alias YouCongressWeb.OpinionLive.OpinionComponent

  @max_x_length 280
  @url_length String.length("youcongress.com/p/should-tech-")

  attr :opinion, :map, required: true
  attr :delegating, :boolean, required: true
  attr :voting, :map, required: true
  attr :current_user, :map, default: nil
  attr :opinable, :boolean, default: false
  attr :delegable, :boolean, default: false
  attr :liked_opinion_ids, :list, default: []

  def render(assigns) do
    ~H"""
    <div class="pb-4">
      <div>
        <div class="flex justify-between">
          <div>
            <strong><.link href={AuthorLive.Show.author_path(@opinion.author)}><%= @opinion.author.name %><%= if @opinion.twin, do: " AI" %></.link></strong>,
            <span class="text-sm">
              <%= @opinion.author.bio || @opinion.author.description %>
            </span>
          </div>
          <AiQuoteMenu.render
            author={@opinion.author}
            id={@opinion.id}
            opinion={@opinion}
            current_user={@current_user}
            voting={@voting}
            page={:opinion_show}
          />
        </div>
      </div>
      <%= if @opinion.twin do %>
        <div class="text-xs text-gray-600">
          would say according to AI:
        </div>
      <% end %>
      <div class="pt-2">
        <%= @opinion.content %>
        <%= if @opinion.source_url do %>
          <span class="text-xs">
            (<.link href={@opinion.source_url} target="_blank" class="underline">source</.link>)
          </span>
        <% end %>
      </div>
      <div class="flex justify-between pt-4 pb-4">
        <div>
          <span :if={@opinable} class="pr-2">
            <OpinionComponent.like_icon opinion={@opinion} liked={@opinion.id in @liked_opinion_ids} />
          </span>
          <span class="pr-2">
            <OpinionComponent.comment_icon :if={@opinable} opinion={@opinion} />
          </span>
          <OpinionComponent.x_icon
            author={@opinion.author}
            voting={@voting}
            opinion={@opinion}
            current_user={@current_user}
          />
        </div>
        <div>
          <%= if @delegable && (!@current_user || (@opinion.author_id != @current_user.author_id)) do %>
            <div>
              <Tooltip.delegation assigns={assigns} />
              <%= if @delegating do %>
                <.link
                  phx-click="remove-delegation"
                  phx-value-author_id={@opinion.author_id}
                  class="rounded border border-indigo-600 bg-transparent px-2 py-1 text-xs font-semibold text-indigo-600 hover:bg-indigo-600 hover:text-white transition-colors duration-200"
                >
                  Delegating
                </.link>
              <% else %>
                <.link
                  phx-click="add-delegation"
                  phx-value-author_id={@opinion.author_id}
                  class="rounded bg-indigo-50 px-2 py-1 text-xs font-semibold text-indigo-600 shadow-sm hover:bg-indigo-100"
                >
                  Delegate
                </.link>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :opinion, :map, required: true

  def comment_icon(assigns) do
    ~H"""
    <.link href={~p"/comments/#{@opinion.id}"}>
      <img src="/images/comment.svg" alt="Comment" class="h-5 w-5 inline" />
      <span class="text-gray-600 pl-1 text-xs">
        <%= if @opinion.descendants_count > 0, do: @opinion.descendants_count %>
      </span>
    </.link>
    """
  end

  attr :opinion, :map, required: true
  attr :liked, :boolean, default: false

  def like_icon(assigns) do
    ~H"""
    <img
      phx-click={if @liked, do: "unlike", else: "like"}
      phx-value-opinion_id={@opinion.id}
      src={"/images/#{if @liked, do: "filled-heart", else: "heart"}.svg"}
      alt="Comment"
      class="h-5 w-5 inline cursor-pointer"
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
      <img src="/images/x.svg" alt="X" class="h-4 w-4 inline cursor-pointer" />
    </a>
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
