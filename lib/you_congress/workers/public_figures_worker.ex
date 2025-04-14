defmodule YouCongress.Workers.PublicFiguresWorker do
  @moduledoc """
  Generates opinions and votes for a voting.
  """

  @max_attempts 2

  use Oban.Worker, max_attempts: @max_attempts

  require Logger

  alias YouCongress.DigitalTwins.PublicFigures
  alias YouCongress.Votings
  alias YouCongress.Authors
  alias YouCongress.Delegations

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{attempt: attempt}) when attempt == @max_attempts do
    Logger.info("Failed to generate a list of public figures. Max attempts reached.")
    {:cancel, "Max attempts reached."}
  end

  def perform(%Oban.Job{
        args: %{"voting_id" => voting_id, "current_user_author_id" => current_user_author_id}
      }) do
    voting = Votings.get_voting!(voting_id, preload: [votes: :author])
    exclude_existent = Enum.map(voting.votes, & &1.author.name)

    exclude_twin_disabled =
      %{twin_origin: true, twin_enabled: false}
      |> Authors.list_authors()
      |> Enum.map(& &1.name)

    exclude_names = exclude_existent ++ exclude_twin_disabled

    maybe_include_names =
      if current_user_author_id do
        current_user_author_id
        |> Delegations.delegate_ids_by_deleguee_id()
        |> then(&Authors.list_authors(ids: &1))
        |> Enum.map(& &1.name)
        |> Enum.uniq()
      else
        []
      end

    maybe_include_names = maybe_include_names -- exclude_names
    provisional_num = PublicFigures.num_gen_opinions()

    with {:ok, _} <-
           Votings.update_voting(voting, %{
             generating_left: provisional_num,
             generating_total: provisional_num
           }),
         {:ok, %{votes: votes}} <-
           PublicFigures.generate_list(
             voting.title,
             :"gpt-4o",
             maybe_include_names,
             exclude_names
           ),
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
