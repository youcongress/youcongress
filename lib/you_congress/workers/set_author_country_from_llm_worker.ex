defmodule YouCongress.Workers.SetAuthorCountryFromLLMWorker do
  @moduledoc """
  Infers and sets an author's country when an LLM says the profile details are clear enough.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Authors.Author
  alias YouCongress.Authors.CountryInference
  alias YouCongress.Countries
  alias YouCongress.Countries.Country
  alias YouCongress.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"author_id" => author_id}}) do
    case Repo.get(Author, author_id) do
      nil ->
        :ok

      %Author{country_id: country_id} when not is_nil(country_id) ->
        :ok

      %Author{} = author ->
        infer_and_update_country(author)
    end
  end

  defp infer_and_update_country(%Author{} = author) do
    case CountryInference.infer_country(author) do
      {:ok, %{should_update: true, country: country}} ->
        update_country(author, country)

      {:ok, _result} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_country(%Author{} = author, country) do
    with country_name when is_binary(country_name) <- normalize_country(country),
         {:ok, %Country{} = country} <- get_country(country_name),
         {:ok, _author} <- update_author_if_still_without_country(author.id, country) do
      :ok
    else
      nil ->
        Logger.warning(
          "Skipping country update for author #{author.id}: inferred country is blank"
        )

        :ok

      {:unknown_country, country_name} ->
        Logger.warning(
          "Skipping country update for author #{author.id}: unknown inferred country #{inspect(country_name)}"
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_author_if_still_without_country(author_id, %Country{} = country) do
    case Repo.get(Author, author_id) do
      nil ->
        {:ok, nil}

      %Author{country_id: country_id} when not is_nil(country_id) ->
        {:ok, nil}

      %Author{} = author ->
        Authors.update_author(author, %{country_id: country.id})
    end
  end

  defp normalize_country(country) when is_binary(country) do
    country
    |> String.trim()
    |> case do
      "" -> nil
      country -> country
    end
  end

  defp normalize_country(_), do: nil

  defp get_country(country) do
    case Countries.get_country_by_name_or_iso(country) do
      nil -> {:unknown_country, country}
      %Country{} = country -> {:ok, country}
    end
  end
end
