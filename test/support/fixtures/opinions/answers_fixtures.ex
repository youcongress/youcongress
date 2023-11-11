defmodule YouCongress.Votes.AnswersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Votes.Answers` context.
  """

  alias YouCongress.Votes.Answers

  @doc """
  Generate an answer.
  """
  def answer_fixture(attrs \\ %{}) do
    {:ok, answer} =
      attrs
      |> Enum.into(%{
        response: new_unique_response()
      })
      |> Answers.create_answer()

    answer
  end

  defp new_unique_response do
    new = Faker.Lorem.sentence()

    if Answers.get_answer_by_response(new) do
      new_unique_response()
    else
      new
    end
  end
end
