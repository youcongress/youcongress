defmodule YouCongress.DelegationVotes do
  @moduledoc """
  The DelegationVotes context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.Answers
  alias YouCongress.Delegations

  @doc """
  Updates the delegated votes of an author.
  """
  @spec update_author_delegated_votes(integer) :: :ok
  def update_author_delegated_votes(author_id) do
    voting_ids_with_author_direct_votes = voting_ids_with_author_direct_votes(author_id)
    delegate_ids = Delegations.delegate_ids_by_author_id(author_id)
    answers = Answers.basic_response_answer_id_map()

    for voting_id <- voting_ids_voted_by([author_id | delegate_ids]) do
      if voting_id in voting_ids_with_author_direct_votes do
        :direct_vote_exists
      else
        update_votes(voting_id, author_id, delegate_ids, answers)
      end
    end

    :ok
  end

  defp update_votes(voting_id, author_id, delegate_ids, answers) do
    {in_favour, against, neutral} = get_counters(voting_id, delegate_ids)

    cond do
      in_favour == 0 and against == 0 and neutral == 0 ->
        delete_vote_if_exists(voting_id, author_id)

      in_favour > against && in_favour > neutral ->
        vote(voting_id, author_id, answers["Agree"])

      against > in_favour && against > neutral ->
        vote(voting_id, author_id, answers["Disagree"])

      neutral > in_favour && neutral > against ->
        vote(voting_id, author_id, answers["Neutral"])

      true ->
        delete_vote_if_exists(voting_id, author_id)
    end
  end

  @spec update_author_voting_delegated_votes(map) :: :ok | :direct_vote_exists
  def update_author_voting_delegated_votes(%{author_id: author_id, voting_id: voting_id}) do
    if Votes.get_vote(%{author_id: author_id, voting_id: voting_id, direct: true}) do
      :direct_vote_exists
    else
      delegate_ids = Delegations.delegate_ids_by_author_id(author_id)
      answers = Answers.basic_response_answer_id_map()
      update_votes(voting_id, author_id, delegate_ids, answers)
      :ok
    end
  end

  defp vote(voting_id, author_id, answer_id) do
    case Votes.get_vote(%{voting_id: voting_id, author_id: author_id}) do
      nil ->
        Votes.create_vote(%{
          voting_id: voting_id,
          author_id: author_id,
          answer_id: answer_id,
          direct: false
        })

      vote ->
        if vote.answer_id != answer_id do
          Votes.update_vote(vote, %{answer_id: answer_id})
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

    in_favour = count(votes, ["Strongly agree", "Agree"])
    against = count(votes, ["Strongly disagree", "Disagree"])
    neutral = count(votes, ["Neutral"])
    {in_favour, against, neutral}
  end

  defp count(votes, responses) do
    Enum.count(votes, fn vote ->
      Answers.basic_answer_id_response_map()[vote.answer_id] in responses
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
