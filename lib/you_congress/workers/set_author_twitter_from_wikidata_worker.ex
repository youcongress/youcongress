defmodule YouCongress.Workers.SetAuthorTwitterFromWikidataWorker do
  @moduledoc """
  Reads an author's `wikidata` id and, when it has no `twitter_username` yet,
  fetches the X (Twitter) username (P2002) and numeric user id (P6552) from
  Wikidata and stores them in `twitter_username` and `twitter_id_str`.

  Enqueue with `%{author_id: author.id}`.
  """

  use Oban.Worker, queue: :wikidata, unique: [states: [:scheduled, :available]]

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Authors.Author
  alias YouCongress.Repo
  alias YouCongress.Wikidata

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"author_id" => author_id}}) do
    case Repo.get(Author, author_id) do
      nil ->
        :ok

      %Author{wikidata: nil} ->
        :ok

      %Author{twitter_username: username} when is_binary(username) and username != "" ->
        :ok

      %Author{} = author ->
        fetch_and_store(author)
    end
  end

  defp fetch_and_store(%Author{} = author) do
    case Wikidata.get_twitter(author.wikidata) do
      {:ok, %{username: nil}} ->
        Logger.info("No X username found for author #{author.id} (#{author.wikidata})")
        :ok

      {:ok, twitter} ->
        update_twitter(author, twitter)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_twitter(%Author{} = author, %{username: username, id_str: id_str}) do
    attrs =
      %{twitter_username: username}
      |> maybe_put(:twitter_id_str, id_str)

    case Authors.update_author(author, attrs) do
      {:ok, _author} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)
end
