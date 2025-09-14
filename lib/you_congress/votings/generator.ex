defmodule YouCongress.Votings.Generator do
  @moduledoc """
  Main module for generating new voting topics and managing the generation process.
  """

  alias YouCongress.Votings
  alias YouCongress.Votings.GeneratorAI

  def generate do
    with {:ok, %{voting_title: voting_title}} <- generator_implementation().generate(),
         {:ok, voting} <- Votings.create_voting(%{title: voting_title}) do
      {:ok, voting}
    end
  end

  defp generator_implementation do
    Application.get_env(:you_congress, :voting_generator, GeneratorAI)
  end
end
