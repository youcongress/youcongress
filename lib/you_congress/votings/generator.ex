defmodule YouCongress.Votings.Generator do
  alias YouCongress.Votings
  alias YouCongress.Votings.GeneratorAI
  alias YouCongress.Workers.PublicFiguresWorker

  def generate do
    with {:ok, %{voting_title: voting_title}} <- generator_implementation().generate(),
         {:ok, voting} <- Votings.create_voting(%{title: voting_title}) do
      %{voting_id: voting.id}
      |> PublicFiguresWorker.new()
      |> Oban.insert()

      {:ok, voting}
    end
  end

  defp generator_implementation do
    Application.get_env(:you_congress, :voting_generator, GeneratorAI)
  end
end
