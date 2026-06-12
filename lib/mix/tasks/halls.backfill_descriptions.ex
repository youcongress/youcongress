defmodule Mix.Tasks.Halls.BackfillDescriptions do
  @moduledoc """
  Generates AI intro descriptions for halls that have statements.

  ## Options

    * `--limit` - maximum number of halls to process
    * `--force` - regenerate descriptions for halls that already have one
  """

  use Mix.Task

  alias YouCongress.Halls
  alias YouCongress.Halls.DescriptionGenerator

  @shortdoc "Generates hall topic-hub descriptions via OpenAI"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [limit: :integer, force: :boolean])

    halls =
      Halls.list_halls_with_statements()
      |> then(fn halls ->
        if opts[:force], do: halls, else: Enum.filter(halls, &is_nil(&1.description))
      end)
      |> then(fn halls ->
        if opts[:limit], do: Enum.take(halls, opts[:limit]), else: halls
      end)

    Mix.shell().info("Generating descriptions for #{length(halls)} halls...")

    Enum.each(halls, fn hall ->
      case DescriptionGenerator.generate(hall.name) do
        {:ok, description} ->
          {:ok, _} = Halls.update_hall(hall, %{description: description})
          Mix.shell().info("✓ #{hall.name}: #{description}")

        {:error, error} ->
          Mix.shell().error("✗ #{hall.name}: #{inspect(error)}")
      end
    end)
  end
end
