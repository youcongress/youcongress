defmodule YouCongress.StatementsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Statements` context.
  """

  @doc """
  Generate a voting.
  """
  def statement_fixture(attrs \\ %{}) do
    {:ok, voting} =
      attrs
      |> Enum.into(%{
        title: Faker.Lorem.sentence()
      })
      |> YouCongress.Statements.create_statement()

    voting
  end
end
