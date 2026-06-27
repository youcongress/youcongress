defmodule YouCongress.Workers.SetAuthorXProfileDataWorker do
  @moduledoc """
  Fetches an author's profile from the X API using their X username and updates
  X-sourced profile fields.
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
        set_x_profile_data(author)
    end
  end

  defp set_x_profile_data(author) do
    case Authors.set_x_profile_data(author) do
      {:ok, _author} ->
        :ok

      # Don't retry when the author can't have X profile data fetched.
      {:error, :no_twitter_username} ->
        :ok

      {:error, :no_profile_image} ->
        :ok

      # The X account no longer exists: remove the stale username
      {:error, "User not found"} ->
        Authors.update_author(author, %{twitter_username: nil})
        :ok

      # Retry on transient errors (rate limits, network, missing config)
      {:error, reason} ->
        {:error, reason}
    end
  end
end
