defmodule YouCongressWeb.OpinionLive.OpinionComponent do
  use Phoenix.Component

  alias YouCongressWeb.AuthorLive
  alias YouCongressWeb.VotingLive.VoteComponent.AiQuoteMenu
  alias YouCongressWeb.Tools.Tooltip
  alias YouCongressWeb.OpinionLive.OpinionComponent

  attr :opinion, :map, required: true
  attr :delegating, :boolean, required: true
  attr :voting, :map, required: true
  attr :current_user, :map, default: nil
  attr :opinable, :boolean, default: false
  attr :delegable, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div class="pt-6 pb-4">
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
          <OpinionComponent.comment_icon :if={@opinable} opinion={@opinion} />
        </div>
        <div>
          <%= if @delegable && (!@current_user || (@opinion.author_id != @current_user.id)) do %>
            <div>
              <Tooltip.delegation assigns={assigns} />

              <.link
                phx-click={if @delegating, do: "remove-delegation", else: "add-delegation"}
                phx-value-author_id={@opinion.author.id}
                phx-value-opinion_id={@opinion.id}
                class="rounded bg-indigo-50 px-2 py-1 text-xs font-semibold text-indigo-600 shadow-sm hover:bg-indigo-100"
              >
                <%= if @delegating, do: "Delegating", else: "Delegate" %>
              </.link>
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
    <.link href={"/comments/#{@opinion.id}#reply"}>
      <img src="/images/comment.svg" alt="Comment" class="h-4 w-4 inline" />
      <span class="text-gray-600 pl-1 text-xs">
        <%= if @opinion.descendants_count > 0, do: @opinion.descendants_count %>
      </span>
    </.link>
    """
  end
end
