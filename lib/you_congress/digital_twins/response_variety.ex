defmodule YouCongress.DigitalTwins.ResponseVariety do
  @moduledoc """
  Calculate the next response based on the previous responses.
  """
  def next_response(votes) do
    case Enum.map(votes, & &1.answer.response) do
      [] ->
        nil

      responses ->
        responses
        |> Enum.random()
        |> next_response(:rand.uniform() < 0.5, :rand.uniform() < 0.5)
    end
  end

  defp next_response("Agree", true, true), do: "Disagree"
  defp next_response("Agree", true, false), do: "Strongly disagree"
  defp next_response("Disagree", true, true), do: "Agree"
  defp next_response("Disagree", true, false), do: "Strongly agree"
  defp next_response("Strongly agree", true, true), do: "Strongly disagree"
  defp next_response("Strongly agree", true, false), do: "Disagree"
  defp next_response("Strongly disagree", true, true), do: "Strongly agree"
  defp next_response("Strongly disagree", true, false), do: "Agree"

  defp next_response(_, _, _), do: nil
end
