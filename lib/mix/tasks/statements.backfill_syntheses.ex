defmodule Mix.Tasks.Statements.BackfillSyntheses do
  @moduledoc """
  Enqueues AI quote-synthesis generation for statements with enough quotes.

  ## Options

    * `--limit` - maximum number of statements to enqueue
    * `--force` - also regenerate statements that already have a synthesis
    * `--dry-run` - only print the candidate statements
    * `--stagger` - seconds between submissions (default 60)

  The `quote_synthesis` feature flag must be enabled in the running app for
  the workers to actually submit; jobs enqueued while it is off skip silently.

  On the Fly release (no Mix) run instead:

      /app/bin/you_congress rpc 'YouCongress.Statements.Synthesis.backfill([])'
  """

  use Mix.Task

  alias YouCongress.FeatureFlags
  alias YouCongress.Statements.Synthesis

  @shortdoc "Enqueues statement quote-synthesis generation via OpenAI"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [limit: :integer, force: :boolean, dry_run: :boolean, stagger: :integer]
      )

    unless FeatureFlags.enabled?(:quote_synthesis) do
      Mix.shell().error(
        "Warning: the quote_synthesis feature flag is disabled — enqueued jobs will skip until it is enabled."
      )
    end

    candidates =
      Synthesis.backfill(
        force: opts[:force],
        limit: opts[:limit],
        dry_run: opts[:dry_run],
        stagger_in_seconds: opts[:stagger] || 60
      )

    action = if opts[:dry_run], do: "Would enqueue", else: "Enqueued"
    Mix.shell().info("#{action} synthesis for #{length(candidates)} statements:")

    Enum.each(candidates, fn {statement, count} ->
      Mix.shell().info("  ##{statement.id} (#{count} quotes) #{statement.title}")
    end)
  end
end
