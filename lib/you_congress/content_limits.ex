defmodule YouCongress.ContentLimits do
  @moduledoc """
  Shared character and byte limits for text that is stored or sent to external
  services. Byte ceilings keep multi-byte input from bypassing storage and cost
  budgets that are expressed in payload size.
  """

  import Ecto.Changeset, only: [validate_length: 3]

  @spec validate_text(Ecto.Changeset.t(), atom(), pos_integer(), pos_integer()) ::
          Ecto.Changeset.t()
  def validate_text(changeset, field, max_characters, max_bytes) do
    changeset
    |> validate_length(field, max: max_characters)
    |> validate_length(field,
      max: max_bytes,
      count: :bytes,
      message: "should be at most %{count} bytes"
    )
  end
end
