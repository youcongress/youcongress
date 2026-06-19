defmodule YouCongress.Workers.SyncAllAuthorsTwitterFromWikidataWorker do
  @moduledoc """
  Finds all authors with a wikidata id but no twitter_username and enqueues
  a SetAuthorTwitterFromWikidataWorker job for each one.

  Jobs are staggered to be gentle on the Wikidata API.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  import Ecto.Query

  alias YouCongress.Authors.Author
  alias YouCongress.Repo
  alias YouCongress.Workers.SetAuthorTwitterFromWikidataWorker

  @stagger_interval 2

  @impl true
  def perform(%Oban.Job{}) do
    Author
    |> where(
      [a],
      not is_nil(a.wikidata) and a.wikidata != "" and
        (is_nil(a.twitter_username) or a.twitter_username == "")
    )
    |> select([a], a.id)
    |> Repo.all()
    |> Enum.with_index()
    |> Enum.each(fn {author_id, index} ->
      %{author_id: author_id}
      |> SetAuthorTwitterFromWikidataWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end
end
