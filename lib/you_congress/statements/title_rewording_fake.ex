defmodule YouCongress.Statements.TitleRewordingFake do
  @moduledoc """
  Generate fake titles for statements.
  """

  def generate_rewordings(_prompt, _model) do
    statements = Enum.map(1..3, fn _ -> Faker.Lorem.sentence() end)
    {:ok, statements, 0}
  end
end
