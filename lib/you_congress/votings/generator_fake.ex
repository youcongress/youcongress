defmodule YouCongress.Votings.GeneratorFake do
  def generate do
    {:ok, %{voting_title: Faker.Lorem.sentence()}}
  end
end
