defmodule YouCongress.Workers.OpinatorWorker do
  @moduledoc """
  Generates opinions and votes for a voting.
  """

  use Oban.Worker

  require Logger

  alias YouCongress.DigitalTwins
  alias YouCongress.Votings
  alias YouCongress.Delegations
  alias YouCongress.DelegationVotes

  @num_gen_opinions_in_prod 15
  @num_gen_opinions_in_dev 2
  @num_gen_opinions_in_test 2

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"voting_id" => voting_id}}) do
    voting = Votings.get_voting!(voting_id)

    num_left =
      if voting.generating_left == 0 do
        num = num_gen_opinions()
        Votings.update_voting(voting, %{generating_left: num})
        num
      else
        voting.generating_left
      end

    case DigitalTwins.generate_vote(voting_id) do
      {:ok, vote} ->
        refresh_delegated_votes(vote, voting_id)
        next(voting, num_left)

      {:error, error} ->
        Logger.error("Failed to generate vote. Skipping. error: #{inspect(error)}")
        next(voting, num_left)
    end
  end

  defp next(voting, num_left) do
    next_num_left = num_left - 1
    {:ok, voting} = Votings.update_voting(voting, %{generating_left: next_num_left})

    if next_num_left > 0 do
      %{voting_id: voting.id}
      |> __MODULE__.new()
      |> Oban.insert()
    end

    :ok
  end

  def num_gen_opinions do
    case Mix.env() do
      :test -> @num_gen_opinions_in_test
      :dev -> @num_gen_opinions_in_dev
      _ -> @num_gen_opinions_in_prod
    end
  end

  defp refresh_delegated_votes(vote, voting_id) do
    delegate_id = vote.author_id
    deleguee_ids = Delegations.deleguee_ids_by_delegate_id(delegate_id)

    for deleguee_id <- deleguee_ids do
      DelegationVotes.update_author_voting_delegated_votes(%{
        author_id: deleguee_id,
        voting_id: voting_id
      })
    end
  end
end
