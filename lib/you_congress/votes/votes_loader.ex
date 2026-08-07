defmodule YouCongressWeb.StatementLive.Show.VotesLoader do
  @moduledoc """
  Loads statement and votes.

  Votes with an opinion are paginated: the page renders the first `per_page`
  and appends the next ones as the visitor scrolls (see `load_more_votes/1`).
  """

  import Phoenix.Component, only: [assign: 2]

  alias YouCongress.FeatureFlags
  alias YouCongress.Opinions
  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Statements.Synthesis
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongress.Delegations
  alias YouCongress.Accounts.User

  @per_page 30

  @spec per_page :: pos_integer
  def per_page, do: @per_page

  @spec load_statement_and_votes(Socket.t(), number) :: Socket.t()
  def load_statement_and_votes(socket, statement_id) do
    %{
      assigns: %{
        current_user: current_user,
        source_filter: source_filter,
        answer_filter: answer_filter,
        selected_country: selected_country
      }
    } = socket

    statement = Statements.get_statement!(statement_id, preload: [:halls])
    current_user_vote = get_current_user_vote(statement, current_user)
    exclude_ids = (current_user_vote && [current_user_vote.id]) || []

    answer = answer_filter_to_atom(answer_filter)

    quotes_votes_count =
      Votes.count_with_opinion_source(statement_id,
        source_filter: :quotes,
        answer: answer,
        author_country: selected_country
      )

    users_votes_count =
      Votes.count_with_opinion_source(statement_id,
        source_filter: :users,
        answer: answer,
        author_country: selected_country
      )

    opts = votes_with_opinion_opts(exclude_ids, source_filter, answer, selected_country)

    # A reload (a new vote, a "reload changes" click) refetches every page the
    # visitor has already scrolled through, so they don't lose their place.
    pages = Map.get(socket.assigns, :opinions_page, 1)
    loaded_limit = pages * @per_page

    votes_with_opinion =
      Votes.list_votes_with_opinion(statement_id, opts ++ [limit: loaded_limit, offset: 0])

    votes_without_opinion =
      case source_filter do
        nil -> Votes.list_votes_without_opinion(statement_id, opts)
        _ -> []
      end

    votes_from_delegates = get_votes_from_delegates(votes_with_opinion, current_user)

    share_to_x_text =
      x_post(current_user_vote, statement) <> " https://youcongress.org/p/#{statement.slug}"

    # Unfiltered quote tally: unlike quotes_votes_count above, it ignores the
    # answer filter, so the synthesis card does not disappear when a visitor
    # filters votes by answer.
    quotes_tally = Votes.count_by_response_map_by_source(statement_id, source_filter: :quotes)
    show_synthesis_card? = show_synthesis_card?(statement, quotes_tally)

    socket
    |> assign(
      statement: statement,
      quotes_tally: quotes_tally,
      show_synthesis_card?: show_synthesis_card?,
      synthesis_opinions: synthesis_opinions(statement, show_synthesis_card?),
      votes_from_delegates: votes_from_delegates,
      votes_from_non_delegates: votes_with_opinion -- votes_from_delegates,
      votes_without_opinion: votes_without_opinion,
      opinions_page: pages,
      has_more_opinions: length(votes_with_opinion) == loaded_limit,
      # Only the first page: keeps the JSON-LD blob small and stable while scrolling.
      seo_votes: Enum.take(votes_with_opinion, @per_page),
      current_user_vote: current_user_vote,
      share_to_x_text: share_to_x_text,
      quotes_votes_count: quotes_votes_count,
      seo_quote_authors: Votes.list_top_sourced_statement_authors(statement_id, 3),
      users_votes_count: users_votes_count,
      total_opinions:
        Votes.count_by(statement_id: statement_id, author_country: selected_country),
      opinions_by_response:
        get_opinions_by_response(statement.id, source_filter, selected_country),
      vote_frequencies: VoteFrequencies.get(statement_id),
      total_votes: Votes.count_by_statement(statement_id)
    )
    |> assign_main_variables(statement, current_user)
  end

  @doc """
  Appends the next page of votes with opinion to the already-loaded ones.
  """
  @spec load_more_votes(Socket.t()) :: Socket.t()
  def load_more_votes(%{assigns: %{has_more_opinions: false}} = socket), do: socket

  def load_more_votes(socket) do
    %{
      assigns: %{
        statement: statement,
        current_user: current_user,
        current_user_vote: current_user_vote,
        source_filter: source_filter,
        answer_filter: answer_filter,
        selected_country: selected_country,
        opinions_page: page,
        votes_from_delegates: votes_from_delegates,
        votes_from_non_delegates: votes_from_non_delegates
      }
    } = socket

    exclude_ids = (current_user_vote && [current_user_vote.id]) || []
    answer = answer_filter_to_atom(answer_filter)
    opts = votes_with_opinion_opts(exclude_ids, source_filter, answer, selected_country)

    new_votes =
      Votes.list_votes_with_opinion(
        statement.id,
        opts ++ [limit: @per_page, offset: page * @per_page]
      )

    new_from_delegates = get_votes_from_delegates(new_votes, current_user)

    socket
    |> assign(
      votes_from_delegates: votes_from_delegates ++ new_from_delegates,
      votes_from_non_delegates: votes_from_non_delegates ++ (new_votes -- new_from_delegates),
      opinions_page: page + 1,
      has_more_opinions: length(new_votes) == @per_page
    )
    |> load_delegations(current_user)
  end

  defp votes_with_opinion_opts(exclude_ids, source_filter, answer, selected_country) do
    opts = [
      include: [:author, opinion: :author],
      exclude_ids: exclude_ids,
      source_filter: source_filter,
      author_country: selected_country
    ]

    if is_nil(answer), do: opts, else: [{:answer, answer} | opts]
  end

  defp answer_filter_to_atom(answer_filter) when answer_filter in ["", nil], do: nil

  defp answer_filter_to_atom(answer_filter) do
    answer_filter |> String.downcase() |> String.to_existing_atom()
  end

  defp show_synthesis_card?(statement, quotes_tally) do
    FeatureFlags.enabled?(:quote_synthesis) and not is_nil(statement.synthesis) and
      Enum.sum(Map.values(quotes_tally)) >= Synthesis.min_quotes()
  end

  # The quotes the synthesis cites, resolved from the database so the card
  # renders real quote content and authors (never LLM-generated quote text).
  # Restricting to the statement's current quotes makes stale cited ids
  # (deleted or detached quotes) vanish instead of erroring.
  defp synthesis_opinions(_statement, false), do: %{}

  defp synthesis_opinions(statement, true) do
    Opinions.list_opinions(
      ids: Synthesis.cited_opinion_ids(statement.synthesis),
      statement_ids: [statement.id],
      only_quotes: true,
      preload: [:author]
    )
    |> Map.new(&{&1.id, &1})
  end

  defp get_opinions_by_response(statement_id, source_filter, author_country) do
    case source_filter do
      :quotes ->
        Votes.count_by_response_map_by_source(statement_id,
          source_filter: :quotes,
          author_country: author_country
        )

      :users ->
        Votes.count_by_response_map_by_source(statement_id,
          source_filter: :users,
          author_country: author_country
        )

      _ ->
        Votes.count_by_response_map(statement_id,
          has_opinion_id: true,
          author_country: author_country
        )
    end
  end

  defp x_post(nil, statement), do: statement.title

  defp x_post(%{opinion_id: nil, direct: false} = current_user_vote, statement) do
    statement.title <> " " <> to_string(current_user_vote.answer) <> " via delegates"
  end

  defp x_post(%{opinion_id: nil} = current_user_vote, statement) do
    statement.title <> " " <> to_string(current_user_vote.answer)
  end

  defp x_post(current_user_vote, statement) do
    statement.title <> " " <> current_user_vote.opinion.content
  end

  @spec get_current_user_vote(Statement.t(), User.t() | nil) :: Vote.t() | nil
  def get_current_user_vote(_, nil), do: nil

  def get_current_user_vote(statement, current_user) do
    Votes.get_current_user_vote(statement.id, current_user.author_id)
  end

  @spec assign_main_variables(Socket.t(), Statement.t(), User.t() | nil) :: Socket.t()
  def assign_main_variables(socket, statement, current_user) do
    socket
    |> load_delegations(current_user)
    |> assign_current_user_vote(statement, current_user)
  end

  defp load_delegations(socket, current_user) do
    %{
      assigns: %{
        votes_from_delegates: votes_from_delegates,
        votes_from_non_delegates: votes_from_non_delegates,
        votes_without_opinion: votes_without_opinion
      }
    } = socket

    author_ids =
      Enum.map(votes_from_delegates, & &1.author_id) ++
        Enum.map(votes_from_non_delegates, & &1.author_id) ++
        Enum.map(votes_without_opinion, & &1.author_id)

    delegate_ids =
      if current_user,
        do: Delegations.delegate_ids_by_deleguee_id(current_user.author_id),
        else: []

    delegations =
      Enum.reduce(author_ids, %{}, fn author_id, acc ->
        Map.put(acc, author_id, !!Enum.find(delegate_ids, &(&1 == author_id)))
      end)

    assign(socket, delegations: delegations)
  end

  @spec get_votes_from_delegates([Vote.t()], User.t() | nil) :: [Vote.t()] | []
  defp get_votes_from_delegates(_, nil), do: []

  defp get_votes_from_delegates(votes, current_user) do
    delegate_ids = Delegations.delegate_ids_by_deleguee_id(current_user.author_id)
    Enum.filter(votes, fn vote -> vote.author_id in delegate_ids end)
  end

  defp assign_current_user_vote(socket, statement, current_user) do
    assign(socket, current_user_vote: get_current_user_vote(statement, current_user))
  end
end
