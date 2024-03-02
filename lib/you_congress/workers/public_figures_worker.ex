defmodule YouCongress.Workers.PublicFiguresWorker do
  @moduledoc """
  Generates opinions and votes for a voting.
  """

  use Oban.Worker

  require Logger

  alias YouCongress.DigitalTwins.PublicFigures
  alias YouCongress.Votings

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"voting_id" => voting_id}}) do
    voting = Votings.get_voting!(voting_id, preload: [votes: :author])

    exclude_names = Enum.map(voting.votes, & &1.author.name)

    with {:ok, _} <-
           Votings.update_voting(voting, %{generating_left: PublicFigures.num_gen_opinions()}),
         {:ok, %{names: names}} <-
           PublicFigures.generate_list(voting.title, :"gpt-3.5-turbo-0125", exclude_names) do
      for name <- names do
        %{voting_id: voting_id, name: name}
        |> YouCongress.Workers.OpinatorWorker.new()
        |> Oban.insert()
      end
    else
      {:error, error} ->
        Logger.error("Failed to generate list of public figures. Retry. error: #{inspect(error)}")
        :error
    end
  end
end
