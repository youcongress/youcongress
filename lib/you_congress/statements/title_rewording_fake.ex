defmodule YouCongress.Statements.TitleRewordingFake do
  @moduledoc """
  Generate fake titles for statements.
  """

  def generate_rewordings(_prompt, _model) do
    suggestions =
      Enum.map(1..3, fn _ ->
        title = Faker.Lorem.sentence()
        slug = title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.slice(0..29) |> String.replace(~r/\-$/, "")
        %{title: title, slug: slug}
      end)

    {:ok, suggestions, 0}
  end
end
