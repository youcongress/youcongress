defmodule YouCongress.Halls.ClassificationBehaviour do
  @moduledoc """
  This module defines the behaviour for classifying a text.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @callback classify(binary, OpenAIModel.t()) ::
              {:ok, %{tags: [binary], cost: number}} | {:error, binary}
end
