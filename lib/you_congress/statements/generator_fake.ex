defmodule YouCongress.Statements.GeneratorFake do
  @moduledoc """
  A fake implementation of the statement generator for testing purposes.
  """

  def generate do
    {:ok, %{statement_title: Faker.Lorem.sentence()}}
  end
end
