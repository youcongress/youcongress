defmodule YouCongressWeb.QuoteReviewLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok,
     socket
     |> assign(:page_title, "Review Quotes")
     |> assign(:pending_quotes, [])
     |> assign(:page, 1)
     |> assign(:per_page, 20)
     |> assign(:has_more, true)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, load_pending_quotes(socket, 1)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply, load_pending_quotes(socket, socket.assigns.page + 1)}
  end

  def handle_event("verify", %{"id" => id}, socket) do
    opinion = Opinions.get_opinion!(String.to_integer(id))

    verifier_id = socket.assigns.current_user && socket.assigns.current_user.id

    case Opinions.update_opinion(opinion, %{is_verified: true, verified_by_user_id: verifier_id}) do
      {:ok, _} ->
        {:noreply, remove_from_list(socket, opinion.id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to verify quote")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    opinion = Opinions.get_opinion!(String.to_integer(id))

    case Opinions.delete_opinion(opinion) do
      {:ok, _} ->
        {:noreply, remove_from_list(socket, opinion.id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete quote")}
    end
  end

  defp remove_from_list(socket, id) do
    list = Enum.reject(socket.assigns.pending_quotes, &(&1.id == id))
    assign(socket, :pending_quotes, list)
  end

  defp load_pending_quotes(socket, page) do
    %{assigns: %{per_page: per_page}} = socket
    offset = (page - 1) * per_page

    quotes =
      Opinions.list_opinions(
        only_quotes: true,
        is_verified: false,
        order_by: [desc: :inserted_at],
        limit: per_page,
        offset: offset,
        preload: [:author, :votings]
      )

    has_more = length(quotes) == per_page

    socket
    |> assign(:pending_quotes, if(page == 1, do: quotes, else: socket.assigns.pending_quotes ++ quotes))
    |> assign(:page, page)
    |> assign(:has_more, has_more)
  end
end
