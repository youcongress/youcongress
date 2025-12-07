defmodule YouCongress.DelegationVotes do
  @moduledoc """
  The DelegationVotes context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Delegations

  @doc """
  Updates the delegated votes of an author.
  """
  @spec update_author_delegated_votes(integer) :: :ok
  def update_author_delegated_votes(author_id) do
    voting_ids_with_author_direct_votes = voting_ids_with_author_direct_votes(author_id)
    delegate_ids = Delegations.delegate_ids_by_deleguee_id(author_id)

    for voting_id <- voting_ids_voted_by([author_id | delegate_ids]) do
      if voting_id in voting_ids_with_author_direct_votes do
        {:ok, :direct_vote_exists}
      else
        update_votes(voting_id, author_id, delegate_ids)
      end
    end

    :ok
  end

  def update_delegated_votes(%{deleguee_id: deleguee_id, delegate_id: delegate_id}) do
    voting_ids_with_deleguee_direct_votes = voting_ids_with_author_direct_votes(deleguee_id)
    delegate_ids = Delegations.delegate_ids_by_deleguee_id(deleguee_id)

    for voting_id <- voting_ids_voted_by([delegate_id]) do
      if voting_id in voting_ids_with_deleguee_direct_votes do
        {:ok, :direct_vote_exists}
      else
        update_votes(voting_id, deleguee_id, delegate_ids)
      end
    end

    :ok
  end

  def update_author_voting_delegated_votes(author_id, voting_id) do
    if Votes.get_by(author_id: author_id, voting_id: voting_id, direct: true) do
      :direct_vote_exists
    else
      delegate_ids = Delegations.delegate_ids_by_deleguee_id(author_id)
      update_votes(voting_id, author_id, delegate_ids)
      :ok
    end
  end

  defp update_votes(voting_id, author_id, delegate_ids) do
    {in_favour, against, neutral} = get_counters(voting_id, delegate_ids)

    cond do
      in_favour == 0 and against == 0 and neutral == 0 ->
        delete_vote_if_exists(voting_id, author_id)

      in_favour > against && in_favour > neutral ->
        vote(voting_id, author_id, :for)

      against > in_favour && against > neutral ->
        vote(voting_id, author_id, :against)

      neutral > in_favour && neutral > against ->
        vote(voting_id, author_id, :abstain)

      true ->
        delete_vote_if_exists(voting_id, author_id)
    end
  end

  @spec update_author_voting_delegated_votes(map) :: :ok | :direct_vote_exists
  def update_author_voting_delegated_votes(%{author_id: author_id, voting_id: voting_id}) do
    if Votes.get_by(author_id: author_id, voting_id: voting_id, direct: true) do
      :direct_vote_exists
    else
      delegate_ids = Delegations.delegate_ids_by_deleguee_id(author_id)
      update_votes(voting_id, author_id, delegate_ids)
      :ok
    end
  end

  defp vote(voting_id, author_id, answer) do
    case Votes.get_by(voting_id: voting_id, author_id: author_id) do
      nil ->
        Votes.create_vote(%{
          voting_id: voting_id,
          author_id: author_id,
          answer: answer,
          direct: false
        })

      vote ->
        if vote.answer != answer do
          Votes.update_vote(vote, %{answer: answer})
        else
          {:ok, vote}
        end
    end
  end

  defp delete_vote_if_exists(voting_id, author_id) do
    Votes.delete_vote(%{voting_id: voting_id, author_id: author_id})
  end

  @spec get_counters(integer, [integer]) :: {integer, integer, integer}
  defp get_counters(voting_id, delegate_ids) do
    votes = votes_from_delegates(voting_id, delegate_ids)

    in_favour = count(votes, [:for])
    against = count(votes, [:against])
    abstain = count(votes, [:abstain])
    {in_favour, against, abstain}
  end

  defp count(votes, responses) do
    Enum.count(votes, fn vote ->
      vote.answer in responses
    end)
  end

  defp voting_ids_with_author_direct_votes(author_id) do
    from(v in Vote,
      where: v.author_id == ^author_id,
      where: v.direct == true,
      select: v.voting_id,
      distinct: true
    )
    |> Repo.all()
  end

  defp voting_ids_voted_by(author_ids) do
    from(v in Vote,
      where: v.author_id in ^author_ids,
      select: v.voting_id,
      distinct: true
    )
    |> Repo.all()
  end

  defp votes_from_delegates(voting_id, delegate_ids) do
    from(v in Vote,
      where: v.voting_id == ^voting_id and v.author_id in ^delegate_ids,
      select: v
    )
    |> Repo.all()
  end
end
