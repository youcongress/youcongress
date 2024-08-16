defmodule YouCongressWeb.VotingLive.Show.VotesLoader do
  @moduledoc """
  Loads voting and votes
  """

  import Phoenix.Component, only: [assign: 2]
  import YouCongressWeb.LiveHelpers, only: [assign_counters: 1]

  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Delegations
  alias YouCongress.Accounts.User
  alias YouCongress.Votes.Answers

  @spec load_voting_and_votes(Socket.t(), number) :: Socket.t()
  def load_voting_and_votes(socket, voting_id) do
    %{assigns: %{current_user: current_user}} = socket
    voting = Votings.get_voting!(voting_id)
    current_user_vote = get_current_user_vote(voting, current_user)
    exclude_ids = (current_user_vote && [current_user_vote.id]) || []

    votes_with_opinion =
      Votes.list_votes_with_opinion(voting_id,
        include: [:author, :answer, :opinion],
        exclude_ids: exclude_ids
      )

    votes_without_opinion =
      Votes.list_votes_without_opinion(voting_id,
        include: [:author, :answer, :opinion],
        exclude_ids: exclude_ids
      )

    votes_from_delegates = get_votes_from_delegates(votes_with_opinion, current_user)

    share_to_x_text =
      x_post(current_user_vote, voting) <> " https://youcongress.com/p/#{voting.slug}"

    total_votes =
      get_total_votes(
        current_user_vote,
        length(votes_with_opinion),
        length(votes_without_opinion)
      )

    socket
    |> assign(
      voting: voting,
      votes_from_delegates: votes_from_delegates,
      votes_from_non_delegates: votes_with_opinion -- votes_from_delegates,
      votes_without_opinion: votes_without_opinion,
      current_user_vote: current_user_vote,
      percentage: get_percentage(voting),
      share_to_x_text: share_to_x_text,
      total_votes: total_votes
    )
    |> assign_main_variables(voting, current_user)
  end

  defp get_total_votes(nil, a, b), do: a + b
  defp get_total_votes(_, a, b), do: a + b + 1

  defp x_post(nil, voting), do: voting.title

  defp x_post(%{opinion_id: nil, direct: false} = current_user_vote, voting) do
    voting.title <> " " <> Answers.get_answer(current_user_vote.answer_id) <> " via delegates"
  end

  defp x_post(%{opinion_id: nil} = current_user_vote, voting) do
    voting.title <> " " <> Answers.get_answer(current_user_vote.answer_id)
  end

  defp x_post(current_user_vote, voting) do
    voting.title <> " " <> current_user_vote.opinion.content
  end

  @spec get_current_user_vote(Voting.t(), User.t() | nil) :: Vote.t() | nil
  def get_current_user_vote(_, nil), do: nil

  def get_current_user_vote(voting, current_user) do
    Votes.get_current_user_vote(voting.id, current_user.author_id)
  end

  @spec assign_main_variables(Socket.t(), Voting.t(), User.t() | nil) :: Socket.t()
  def assign_main_variables(socket, voting, current_user) do
    socket
    |> load_delegations(current_user)
    |> assign_counters()
    |> assign_vote_frequencies(voting)
    |> assign_current_user_vote(voting, current_user)
  end

  defp get_percentage(%Voting{generating_total: 0}), do: 100

  defp get_percentage(voting) do
    votes_generated = voting.generating_total - voting.generating_left
    round(votes_generated * 100 / voting.generating_total)
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
      if current_user, do: Delegations.delegate_ids_by_author_id(current_user.author_id), else: []

    delegations =
      Enum.reduce(author_ids, %{}, fn author_id, acc ->
        Map.put(acc, author_id, !!Enum.find(delegate_ids, &(&1 == author_id)))
      end)

    assign(socket, delegations: delegations)
  end

  @spec get_vote_frequencies(Voting.t()) :: %{binary => number}
  defp get_vote_frequencies(voting) do
    vote_frequencies =
      Votes.count_by_response(voting.id)
      |> Enum.into(%{})

    total = Enum.sum(Map.values(vote_frequencies))

    vote_frequencies
    |> Enum.map(fn {k, v} -> {k, {v, round(v * 100 / total)}} end)
    |> Enum.into(%{})
  end

  @spec get_votes_from_delegates([Vote.t()], User.t() | nil) :: [Vote.t()] | []
  defp get_votes_from_delegates(_, nil), do: []

  defp get_votes_from_delegates(votes, current_user) do
    delegate_ids = Delegations.delegate_ids_by_author_id(current_user.author_id)
    Enum.filter(votes, fn vote -> vote.author_id in delegate_ids end)
  end

  defp assign_current_user_vote(socket, voting, current_user) do
    assign(socket, current_user_vote: get_current_user_vote(voting, current_user))
  end

  defp assign_vote_frequencies(socket, voting) do
    assign(socket, vote_frequencies: get_vote_frequencies(voting))
  end
end
