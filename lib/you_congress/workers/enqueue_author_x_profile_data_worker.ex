defmodule YouCongress.Workers.EnqueueAuthorXProfileDataWorker do
  @moduledoc """
  Finds authors with an X username and incomplete X profile data, then enqueues
  a SetAuthorXProfileDataWorker job for each one.

  Jobs are staggered to avoid hitting X API rate limits.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  import Ecto.Query

  alias YouCongress.Authors.Author
  alias YouCongress.Repo
  alias YouCongress.Workers.SetAuthorXProfileDataWorker

  @stagger_interval 4

  @impl true
  def perform(%Oban.Job{}) do
    Author
    |> where(
      [a],
      not is_nil(a.twitter_username) and
        (is_nil(a.profile_image_url) or is_nil(a.twitter_id_str) or
           is_nil(a.followers_count) or is_nil(a.friends_count) or is_nil(a.verified))
    )
    |> select([a], a.id)
    |> Repo.all()
    |> Enum.with_index()
    |> Enum.each(fn {author_id, index} ->
      %{author_id: author_id}
      |> SetAuthorXProfileDataWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end
end
