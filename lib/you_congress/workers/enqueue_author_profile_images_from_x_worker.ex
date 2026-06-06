defmodule YouCongress.Workers.EnqueueAuthorProfileImagesFromXWorker do
  @moduledoc """
  Finds all authors with an X username but no profile image and enqueues
  a SetAuthorProfileImageFromXWorker job for each one.

  Jobs are staggered to avoid hitting X API rate limits.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  import Ecto.Query

  alias YouCongress.Authors.Author
  alias YouCongress.Repo
  alias YouCongress.Workers.SetAuthorProfileImageFromXWorker

  @stagger_interval 4

  @impl true
  def perform(%Oban.Job{}) do
    Author
    |> where([a], is_nil(a.profile_image_url) and not is_nil(a.twitter_username))
    |> select([a], a.id)
    |> Repo.all()
    |> Enum.with_index()
    |> Enum.each(fn {author_id, index} ->
      %{author_id: author_id}
      |> SetAuthorProfileImageFromXWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end
end
