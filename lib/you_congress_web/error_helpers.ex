defmodule YouCongressWeb.ErrorHelpers do
  @moduledoc """
  Helper functions for dealing with errors.
  """

  @doc """
  Extracts errors from a changeset and returns a string.

  ## Examples

      iex> changeset = Ecto.Changeset.cast(%User{}, %{})
      iex> YouCongressWeb.ErrorHelpers.extract_errors(changeset)
      "email can't be blank, password can't be blank"
  """
  def extract_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
  end
end
