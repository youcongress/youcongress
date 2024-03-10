defmodule YouCongress.Workers.PublicFiguresWorker do
  @moduledoc """
  Generates opinions and votes for a voting.
  """

  @max_attempts 2

  use Oban.Worker, max_attempts: @max_attempts

  require Logger

  alias YouCongress.DigitalTwins.PublicFigures
  alias YouCongress.Votings

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{attempt: attempt}) when attempt == @max_attempts do
    Logger.info("Failed to generate a list of public figures. Max attempts reached.")
    {:cancel, "Max attempts reached."}
  end

  def perform(%Oban.Job{args: %{"voting_id" => voting_id}}) do
    voting = Votings.get_voting!(voting_id, preload: [votes: :author])
    exclude_names = Enum.map(voting.votes, & &1.author.name)

    provisional_num = PublicFigures.num_gen_opinions()

    with {:ok, _} <-
           Votings.update_voting(voting, %{
             generating_left: provisional_num,
             generating_total: provisional_num
           }),
         {:ok, %{votes: votes}} <-
           PublicFigures.generate_list(voting.title, :"gpt-3.5-turbo-0125", exclude_names),
         true <- is_list(votes),
         {:ok, _} <-
           Votings.update_voting(voting, %{
             generating_left: length(votes),
             generating_total: length(votes)
           }) do
      for [name, response] <- votes do
        %{voting_id: voting_id, name: name, response: response}
        |> YouCongress.Workers.OpinatorWorker.new()
        |> Oban.insert()
      end

      :ok
    else
      {:error, error} ->
        Logger.error("Failed to generate list of public figures. Retry. error: #{inspect(error)}")
        :error

      true ->
        Logger.error("Failed to generate list of public figures. Retry. error: not a list")
        :error
    end
  end
end
