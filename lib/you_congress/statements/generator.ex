defmodule YouCongress.Statements.Generator do
  @moduledoc """
  Main module for generating new statement topics and managing the generation process.
  """

  alias YouCongress.Statements
  alias YouCongress.Statements.GeneratorAI

  def generate do
    with {:ok, %{statement_title: statement_title}} <- generator_implementation().generate() do
      Statements.create_statement(%{title: statement_title})
    end
  end

  defp generator_implementation do
    Application.get_env(:you_congress, :statement_generator, GeneratorAI)
  end
end
