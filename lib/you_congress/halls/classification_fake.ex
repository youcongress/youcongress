defmodule YouCongress.Halls.ClassificationFake do
  @moduledoc """
  This module mocks the classification behaviour.
  """

  alias YouCongress.Halls.ClassificationBehaviour

  @behaviour ClassificationBehaviour

  @impl ClassificationBehaviour
  def classify(_text, _model) do
    {:ok, %{main_tag: "fake", other_tags: [Faker.Lorem.word()], cost: 0}}
  end
end
