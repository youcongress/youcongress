defmodule YouCongress.Wikidata do
  @moduledoc """
  Resolves the Wikidata entity id (e.g. "Q42") for a Wikipedia URL.

  Dispatches to a configurable implementation so tests and dev can avoid
  hitting the network (see `:wikidata_implementation`).
  """

  @type twitter :: %{username: String.t() | nil, id_str: String.t() | nil}

  @callback get_wikidata_id(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  @callback get_twitter(String.t()) :: {:ok, twitter} | {:error, term()}

  @spec get_wikidata_id(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_wikidata_id(wikipedia_url) do
    implementation().get_wikidata_id(wikipedia_url)
  end

  @doc """
  Returns the X (Twitter) username (P2002) and numeric user id (P6552) for a
  Wikidata entity id (e.g. "Q42").
  """
  @spec get_twitter(String.t()) :: {:ok, twitter} | {:error, term()}
  def get_twitter(wikidata_id) do
    implementation().get_twitter(wikidata_id)
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :wikidata_implementation,
      YouCongress.Wikidata.WikidataApi
    )
  end
end
