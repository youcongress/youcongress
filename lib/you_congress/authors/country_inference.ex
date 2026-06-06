defmodule YouCongress.Authors.CountryInference do
  @moduledoc """
  Infers an author's country from profile details.
  """

  alias YouCongress.Authors.Author
  alias YouCongress.DigitalTwins.OpenAIModel

  @default_model :"gpt-5-nano"

  @type result :: %{
          should_update: boolean(),
          country: binary() | nil,
          reason: binary() | nil
        }

  @callback infer_country(Author.t(), OpenAIModel.t()) :: {:ok, result()} | {:error, binary()}

  @spec infer_country(Author.t(), OpenAIModel.t()) :: {:ok, result()} | {:error, binary()}
  def infer_country(%Author{} = author, model \\ @default_model) do
    implementation().infer_country(author, model)
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :author_country_inference_implementation,
      YouCongress.Authors.CountryInferenceAI
    )
  end
end
