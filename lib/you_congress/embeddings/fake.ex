defmodule YouCongress.Embeddings.Fake do
  @moduledoc false

  @behaviour YouCongress.Embeddings

  @impl YouCongress.Embeddings
  def embed(_text), do: {:error, :embedding_disabled}
end
