defmodule YouCongress.DigitalTwins.PublicFigures do
  @moduledoc """
  Generates a list of public figures who have publicly shared their views on a topic.
  """

  @num_gen_opinions_in_prod 32
  @num_gen_opinions_in_dev 2
  @num_gen_opinions_in_test 2

  alias YouCongress.DigitalTwins.OpenAIModel

  @spec generate_list(binary, OpenAIModel.t(), list | nil) ::
          {:error, binary} | {:ok, %{cost: float, votes: list}}
  def generate_list(topic, model, exclude_names \\ []) do
    implementation().generate_list(topic, model, exclude_names)
  end

  def num_gen_opinions do
    case Application.get_env(:you_congress, :env) do
      :test -> @num_gen_opinions_in_test
      :dev -> @num_gen_opinions_in_dev
      _ -> @num_gen_opinions_in_prod
    end
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :public_figures_generator,
      YouCongress.DigitalTwins.PublicFiguresAI
    )
  end
end
