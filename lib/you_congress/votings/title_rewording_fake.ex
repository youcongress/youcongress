defmodule YouCongress.Votings.TitleRewordingFake do
  @moduledoc """
  Generate fake titles for votings.
  """

  def generate_rewordings(_prompt, _model) do
    votings = Enum.map(1..3, fn _ -> Faker.Lorem.sentence() end)
    {:ok, votings, 0}
  end
end
