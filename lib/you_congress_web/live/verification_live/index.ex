defmodule YouCongressWeb.VerificationLive.Index do
  use YouCongressWeb, :live_view

  import Ecto.Query, warn: false

  alias YouCongress.Repo
  alias YouCongress.Verifications
  alias YouCongress.Verifications.Verification
  alias YouCongress.Votes
  alias YouCongress.Likes
  alias YouCongress.Delegations
  alias YouCongressWeb.StatementLive.{CastVoteComponent, VoteComponent}

  @per_page 20

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Verifications")
     |> assign(:page, 1)
     |> assign(:has_more, true)
     |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))
     |> assign(:delegate_ids, load_delegate_ids(current_user))
     |> load_cards(1)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply, load_cards(socket, socket.assigns.page + 1)}
  end

  @impl true
  def handle_info({:put_flash, kind, msg}, socket) do
    {:noreply, socket |> clear_flash() |> put_flash(kind, msg)}
  end

  def handle_info({:voted, _vote}, socket) do
    {:noreply, socket}
  end

  def handle_info({:verification_saved, _opinion_id}, socket) do
    {:noreply, load_cards(socket, 1)}
  end

  defp load_cards(socket, page) do
    offset = (page - 1) * @per_page
    current_user = socket.assigns.current_user

    # Get distinct opinion_ids ordered by latest verification
    opinion_entries =
      from(v in Verification,
        group_by: v.opinion_id,
        select: %{opinion_id: v.opinion_id, latest: max(v.inserted_at)},
        order_by: [desc: max(v.inserted_at)],
        limit: ^@per_page,
        offset: ^offset
      )
      |> Repo.all()

    opinion_ids = Enum.map(opinion_entries, & &1.opinion_id)

    # Load opinions with author and statements
    opinions =
      from(o in YouCongress.Opinions.Opinion,
        where: o.id in ^opinion_ids,
        preload: [:author, :statements]
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    # Load votes for these opinions (with author and opinion)
    votes =
      from(v in YouCongress.Votes.Vote,
        where: v.opinion_id in ^opinion_ids,
        preload: [:author, :opinion]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.opinion_id)
      |> Map.new(fn {opinion_id, votes} -> {opinion_id, List.first(votes)} end)

    # Load all verifications for these opinions
    all_verifications =
      Verifications.list_verifications(
        opinion_id: opinion_ids,
        order_by: [desc: :updated_at],
        preload: [user: [:author]]
      )

    verifications_by_opinion_id = Enum.group_by(all_verifications, & &1.opinion_id)

    # Build cards in order
    cards =
      opinion_ids
      |> Enum.map(fn opinion_id ->
        opinion = Map.get(opinions, opinion_id)
        vote = Map.get(votes, opinion_id)

        if opinion && vote do
          vote = %{vote | opinion: opinion}

          statement =
            Enum.find(opinion.statements, fn s -> s.id == vote.statement_id end) ||
              List.first(opinion.statements)

          if statement do
            %{
              id: opinion_id,
              opinion: opinion,
              vote: vote,
              statement: statement,
              verifications: Map.get(verifications_by_opinion_id, opinion_id, [])
            }
          end
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Load current user's votes for these statements
    statement_ids = cards |> Enum.map(& &1.statement.id) |> Enum.uniq()
    user_votes = load_user_votes(current_user, statement_ids)
    user_opinions = load_user_opinions(current_user, statement_ids)

    has_more = length(opinion_entries) == @per_page

    socket
    |> assign(:cards, if(page == 1, do: cards, else: socket.assigns.cards ++ cards))
    |> assign(:user_votes, user_votes)
    |> assign(:user_opinions, user_opinions)
    |> assign(:page, page)
    |> assign(:has_more, has_more)
  end

  defp load_user_votes(nil, _), do: %{}
  defp load_user_votes(%{author_id: nil}, _), do: %{}
  defp load_user_votes(_, []), do: %{}

  defp load_user_votes(current_user, statement_ids) do
    Votes.list_votes(
      author_ids: [current_user.author_id],
      statement_ids: statement_ids,
      preload: [:opinion]
    )
    |> Map.new(&{&1.statement_id, &1})
  end

  defp load_user_opinions(nil, _), do: %{}
  defp load_user_opinions(%{author_id: nil}, _), do: %{}
  defp load_user_opinions(_, []), do: %{}

  defp load_user_opinions(current_user, statement_ids) do
    Votes.list_votes(
      author_ids: [current_user.author_id],
      statement_ids: statement_ids,
      preload: [:opinion]
    )
    |> Enum.filter(& &1.opinion_id)
    |> Map.new(&{&1.statement_id, &1.opinion})
  end

  defp load_delegate_ids(nil), do: []
  defp load_delegate_ids(%{author_id: nil}), do: []

  defp load_delegate_ids(%{author_id: author_id}) do
    Delegations.list_delegation_ids(deleguee_id: author_id)
  end

end
