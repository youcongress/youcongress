defmodule YouCongress.Tools.StringUtils do
  def titleize(string) do
    string
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
