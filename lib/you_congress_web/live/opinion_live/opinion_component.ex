defmodule YouCongressWeb.OpinionLive.OpinionComponent do
  use Phoenix.Component

  alias YouCongressWeb.AuthorLive
  alias YouCongressWeb.VotingLive.VoteComponent.AiQuoteMenu
  alias YouCongressWeb.Tools.Tooltip

  attr :opinion, :map, required: true
  attr :delegating, :boolean, required: true
  attr :voting, :map, required: true
  attr :current_user, :map, default: nil
  attr :opinable, :boolean, default: false

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
            voting={@opinion.voting}
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
          <%= if @opinable do %>
            <.link href={"/comments/#{@opinion.id}#reply"}>
              <img src="/images/comment.svg" alt="Comment" class="h-4 w-4 inline" />
            </.link>
          <% end %>
        </div>
        <div>
          <%= if !@current_user || (@opinion.author_id != @current_user.id) do %>
            <div>
              <Tooltip.render
                content={[
                  "Choose a list of delegates",
                  "to vote as the majority of them.",
                  "Unless you vote directly."
                ]}
                position="left"
              >
                <img src="/images/info.svg" alt="Info" class="h-4 w-4 inline" />
              </Tooltip.render>

              <.link
                phx-click={if @delegating, do: "remove-delegation", else: "add-delegation"}
                phx-value-author_id={@opinion.author.id}
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
end
