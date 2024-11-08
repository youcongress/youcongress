defmodule YouCongress.Tools.StringUtils do
  @moduledoc """
  String utilities.
  """

  def titleize(string) do
    string
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def titleize_hall("us"), do: "US"
  def titleize_hall("ai"), do: "AI"
  def titleize_hall("eu"), do: "EU"
  def titleize_hall(hall_name), do: titleize(hall_name)
end
