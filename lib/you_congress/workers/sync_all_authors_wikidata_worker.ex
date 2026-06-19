defmodule YouCongress.Workers.SyncAllAuthorsWikidataWorker do
  @moduledoc """
  Finds all authors with a wikipedia_url but no wikidata id and enqueues
  a SetAuthorWikidataWorker job for each one.

  Jobs are staggered to be gentle on the Wikipedia API.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  import Ecto.Query

  alias YouCongress.Authors.Author
  alias YouCongress.Repo
  alias YouCongress.Workers.SetAuthorWikidataWorker

  @stagger_interval 2

  @impl true
  def perform(%Oban.Job{}) do
    Author
    |> where([a], not is_nil(a.wikipedia_url) and a.wikipedia_url != "" and is_nil(a.wikidata))
    |> select([a], a.id)
    |> Repo.all()
    |> Enum.with_index()
    |> Enum.each(fn {author_id, index} ->
      %{author_id: author_id}
      |> SetAuthorWikidataWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end
end
