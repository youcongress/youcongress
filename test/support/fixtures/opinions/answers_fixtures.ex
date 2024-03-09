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
        response: new_response()
      })
      |> Answers.create_answer()

    answer
  end

  defp new_response do
    Enum.random(YouCongress.Votes.Answers.basic_responses())
  end
end
