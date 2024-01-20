defmodule YouCongress.Workers.OpinatorWorker do
  @moduledoc """
  Generates opinions and votes for a voting.
  """

  use Oban.Worker

  require Logger

  alias YouCongress.DigitalTwins
  alias YouCongress.Votings

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

      {:error, error} ->
        Logger.error("Failed to generate vote. Skipping. error: #{inspect(error)}")
    end

    next_num_left = num_left - 1
    Votings.update_voting(voting, %{generating_left: next_num_left})

    if next_num_left > 0 do
      %{voting_id: voting_id}
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
    %{author_id: vote.author_id, voting_id: voting_id}
    |> YouCongress.Workers.RefreshAuthorVotingDelegatedVotesWorker.new()
    |> Oban.insert()
  end
end
