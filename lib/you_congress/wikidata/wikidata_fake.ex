defmodule YouCongress.Wikidata.WikidataFake do
  @moduledoc """
  Fake Wikidata resolver for test and development without network access.
  """

  @behaviour YouCongress.Wikidata

  @impl YouCongress.Wikidata
  @spec get_wikidata_id(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_wikidata_id(_wikipedia_url), do: {:ok, nil}

  @impl YouCongress.Wikidata
  @spec get_twitter(String.t()) :: {:ok, YouCongress.Wikidata.twitter()} | {:error, term()}
  def get_twitter(_wikidata_id), do: {:ok, %{username: nil, id_str: nil}}
end
