defmodule YouCongress.Wikidata do
  @moduledoc """
  Resolves the Wikidata entity id (e.g. "Q42") for a Wikipedia URL.

  Dispatches to a configurable implementation so tests and dev can avoid
  hitting the network (see `:wikidata_implementation`).
  """

  @callback get_wikidata_id(String.t()) :: {:ok, String.t() | nil} | {:error, term()}

  @spec get_wikidata_id(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_wikidata_id(wikipedia_url) do
    implementation().get_wikidata_id(wikipedia_url)
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :wikidata_implementation,
      YouCongress.Wikidata.WikidataApi
    )
  end
end
