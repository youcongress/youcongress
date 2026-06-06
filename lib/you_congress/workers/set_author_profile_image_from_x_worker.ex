defmodule YouCongress.Workers.SetAuthorProfileImageFromXWorker do
  @moduledoc """
  Fetches an author's profile picture from the X API using their X username
  and updates the author's profile_image_url.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Authors
  alias YouCongress.Authors.Author
  alias YouCongress.Repo

  @impl true
  def perform(%Oban.Job{args: %{"author_id" => author_id}}) do
    case Repo.get(Author, author_id) do
      nil ->
        :ok

      %Author{} = author ->
        set_profile_image(author)
    end
  end

  defp set_profile_image(author) do
    case Authors.set_profile_image_from_x(author) do
      {:ok, _author} ->
        :ok

      # Don't retry when the author can't have an image fetched
      {:error, :no_twitter_username} ->
        :ok

      {:error, :no_profile_image} ->
        :ok

      {:error, "User not found"} ->
        :ok

      # Retry on transient errors (rate limits, network, missing config)
      {:error, reason} ->
        {:error, reason}
    end
  end
end
