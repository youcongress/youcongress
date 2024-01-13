defmodule YouCongress.Tools.Permalink do
  @moduledoc """
  The Permalink context.
  """

  @doc """
  Creates a permalink.

  ## Examples

      iex> permalink(4)
      "MTIz"

  """
  def permalink(bytes_count) do
    bytes_count
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
