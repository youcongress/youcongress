defmodule YouCongress.Tools.StringUtils do
  @moduledoc """
  String utilities.
  """

  def titleize(string) do
    string
    |> String.split("-")
    |> Enum.map_join(" ", fn word ->
      word
      |> String.capitalize()
      |> String.replace("Cern", "CERN")
      |> String.replace("For", "for")
      |> String.replace("Us", "US")
      |> String.replace("Eu", "EU")
      |> String.replace("Ai", "AI")
      |> String.replace("Uk", "UK")
    end)
  end

  def titleize_hall("us"), do: "US"
  def titleize_hall("ai"), do: "AI"
  def titleize_hall("eu"), do: "EU"
  def titleize_hall(hall_name), do: titleize(hall_name)
end
