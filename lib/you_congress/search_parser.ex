defmodule YouCongress.SearchParser do
  @moduledoc """
  Parses search strings, respecting quoted terms.
  """

  @doc """
  Parses a search string into a list of terms.
  Quoted substrings are treated as single terms (without the quotes).

  ## Examples

      iex> YouCongress.SearchParser.parse("hello world")
      ["hello", "world"]

      iex> YouCongress.SearchParser.parse("hello \\"new world\\"")
      ["hello", "new world"]

      iex> YouCongress.SearchParser.parse("\\"state of the art\\"")
      ["state of the art"]
  """
  def parse(nil), do: []
  def parse(""), do: []

  def parse(search_string) do
    search_string =
      if rem(count_quotes(search_string), 2) == 1 do
        search_string <> "\""
      else
        search_string
      end

    # Regex explains:
    # \"[^\"]+\"  -> Matches double-quoted strings (e.g. "foo bar")
    # \S+         -> Matches sequence of non-whitespace characters (normal words)
    Regex.scan(~r/"[^"]+"|[\S]+/, search_string)
    |> List.flatten()
    |> Enum.map(&strip_quotes/1)
  end

  defp count_quotes(str) do
    str
    |> String.graphemes()
    |> Enum.count(&(&1 == "\""))
  end

  defp strip_quotes(term) do
    if String.starts_with?(term, "\"") and String.ends_with?(term, "\"") do
      String.slice(term, 1, String.length(term) - 2)
    else
      term
    end
  end
end
