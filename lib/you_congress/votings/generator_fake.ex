defmodule YouCongress.Votings.GeneratorFake do
  @moduledoc """
  A fake implementation of the voting generator for testing purposes.
  """

  def generate do
    {:ok, %{voting_title: Faker.Lorem.sentence()}}
  end
end
