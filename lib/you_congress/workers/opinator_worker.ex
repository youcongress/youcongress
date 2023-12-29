defmodule YouCongress.Workers.OpinatorWorker do
  @moduledoc """
  Generates opinions and votes for a voting.
  """

  use Oban.Worker

  alias YouCongress.DigitalTwins
  alias YouCongress.Votings

  @num_gen_opinions 5

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"voting_id" => voting_id}}) do
    voting = Votings.get_voting!(voting_id)

    num_left =
      if voting.generating_left == 0 do
        Votings.update_voting(voting, %{generating_left: @num_gen_opinions})
        @num_gen_opinions
      else
        voting.generating_left
      end

    {:ok, vote} = DigitalTwins.generate_vote(voting_id)

    refresh_delegated_votes(vote, voting_id)

    next_num_left = num_left - 1
    Votings.update_voting(voting, %{generating_left: next_num_left})

    if next_num_left > 0 do
      %{voting_id: voting_id}
      |> __MODULE__.new()
      |> Oban.insert()
    end

    :ok
  end

  def num_gen_opinions, do: @num_gen_opinions

  defp refresh_delegated_votes(vote, voting_id) do
    %{author_id: vote.author_id, voting_id: voting_id}
    |> YouCongress.Workers.RefreshAuthorVotingDelegatedVotesWorker.new()
    |> Oban.insert()
  end
end
