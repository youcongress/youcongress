defmodule YouCongress.DigitalTwins.PublicFiguresFake do
  alias YouCongress.DigitalTwins.PublicFigures
  alias YouCongress.DigitalTwins.PublicFigures

  def generate_list(_topic, _model, _exclude_names \\ []) do
    votes =
      Enum.map(1..PublicFigures.num_gen_opinions(), fn _ ->
        [Faker.Person.name(), "Strongly agree"]
      end)

    {:ok, %{votes: votes, cost: 0}}
  end
end
