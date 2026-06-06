defmodule YouCongress.Authors.CountryInferenceFake do
  @moduledoc """
  Fake country inference implementation for test and development without OpenAI.
  """

  alias YouCongress.Authors.Author
  alias YouCongress.Authors.CountryInference
  alias YouCongress.DigitalTwins.OpenAIModel

  @behaviour CountryInference

  @impl CountryInference
  @spec infer_country(Author.t(), OpenAIModel.t()) ::
          {:ok, CountryInference.result()} | {:error, binary()}
  def infer_country(%Author{}, _model) do
    {:ok, %{should_update: false, country: nil, reason: "fake"}}
  end
end
