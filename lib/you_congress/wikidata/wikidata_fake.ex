defmodule YouCongress.Wikidata.WikidataFake do
  @moduledoc """
  Fake Wikidata resolver for test and development without network access.
  """

  @behaviour YouCongress.Wikidata

  @impl YouCongress.Wikidata
  @spec get_wikidata_id(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_wikidata_id(_wikipedia_url), do: {:ok, nil}
end
