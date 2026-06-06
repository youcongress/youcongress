defmodule YouCongressWeb.StatementLive.Show.VotesLoader do
  @moduledoc """
  Loads statement and votes
  """

  import Phoenix.Component, only: [assign: 2]

  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongress.Delegations
  alias YouCongress.Accounts.User

  @spec load_statement_and_votes(Socket.t(), number) :: Socket.t()
  def load_statement_and_votes(socket, statement_id) do
    %{
      assigns: %{
        current_user: current_user,
        source_filter: source_filter,
        answer_filter: answer_filter
      }
    } = socket

    statement = Statements.get_statement!(statement_id, preload: [:halls])
    current_user_vote = get_current_user_vote(statement, current_user)
    exclude_ids = (current_user_vote && [current_user_vote.id]) || []

    answer =
      if answer_filter == "" || is_nil(answer_filter),
        do: nil,
        else: String.downcase(answer_filter) |> String.to_existing_atom()

    quotes_votes_count =
      Votes.count_with_opinion_source(statement_id, source_filter: :quotes, answer: answer)

    users_votes_count =
      Votes.count_with_opinion_source(statement_id, source_filter: :users, answer: answer)

    opts = [
      include: [:author, opinion: :author],
      exclude_ids: exclude_ids,
      source_filter: source_filter
    ]

    opts = if is_nil(answer), do: opts, else: [{:answer, answer} | opts]
    votes_with_opinion = Votes.list_votes_with_opinion(statement_id, opts)

    votes_without_opinion =
      case source_filter do
        nil -> Votes.list_votes_without_opinion(statement_id, opts)
        _ -> []
      end

    votes_from_delegates = get_votes_from_delegates(votes_with_opinion, current_user)

    share_to_x_text =
      x_post(current_user_vote, statement) <> " https://youcongress.org/p/#{statement.slug}"

    socket
    |> assign(
      statement: statement,
      votes_from_delegates: votes_from_delegates,
      votes_from_non_delegates: votes_with_opinion -- votes_from_delegates,
      votes_without_opinion: votes_without_opinion,
      current_user_vote: current_user_vote,
      share_to_x_text: share_to_x_text,
      quotes_votes_count: quotes_votes_count,
      users_votes_count: users_votes_count,
      total_opinions: Votes.count_by(statement_id: statement_id),
      opinions_by_response: get_opinions_by_response(statement.id, source_filter),
      vote_frequencies: VoteFrequencies.get(statement_id),
      total_votes: Votes.count_by_statement(statement_id)
    )
    |> assign_main_variables(statement, current_user)
  end

  defp get_opinions_by_response(statement_id, source_filter) do
    case source_filter do
      :quotes -> Votes.count_by_response_map_by_source(statement_id, source_filter: :quotes)
      :users -> Votes.count_by_response_map_by_source(statement_id, source_filter: :users)
      _ -> Votes.count_by_response_map(statement_id, has_opinion_id: true)
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
