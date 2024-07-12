defmodule YouCongress.Tools.StringUtils do
  @moduledoc """
  String utilities.
  """

  def titleize(string) do
    string
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
