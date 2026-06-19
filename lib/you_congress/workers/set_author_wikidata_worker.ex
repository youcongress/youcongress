defmodule YouCongress.Workers.SetAuthorWikidataWorker do
  @moduledoc """
  Reads an author's `wikipedia_url`, resolves its Wikidata id and stores it
  in the `wikidata` field.

  Enqueue with `%{author_id: author.id}`.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

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

      %Author{wikidata: wikidata} when is_binary(wikidata) ->
        :ok

      %Author{wikipedia_url: nil} ->
        :ok

      %Author{} = author ->
        fetch_and_store(author)
    end
  end

  defp fetch_and_store(%Author{} = author) do
    case Wikidata.get_wikidata_id(author.wikipedia_url) do
      {:ok, nil} ->
        Logger.info("No Wikidata id found for author #{author.id} (#{author.wikipedia_url})")
        :ok

      {:ok, wikidata} ->
        update_wikidata(author, wikidata)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_wikidata(%Author{} = author, wikidata) do
    case Authors.update_author(author, %{wikidata: wikidata}) do
      {:ok, _author} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
