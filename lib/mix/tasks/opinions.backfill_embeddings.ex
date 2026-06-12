defmodule Mix.Tasks.Opinions.BackfillEmbeddings do
  @moduledoc """
  Enqueues an Oban job to backfill the missing embedding of each sourced quote.

  ## Options

    * `--limit` - maximum number of quotes to enqueue
  """

  use Mix.Task

  alias YouCongress.Workers.BackfillOpinionEmbeddingWorker

  @shortdoc "Enqueues sourced quote embedding backfill jobs"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [limit: :integer])

    enqueued = BackfillOpinionEmbeddingWorker.enqueue_all(Keyword.get(opts, :limit))

    Mix.shell().info("Enqueued #{enqueued} embedding backfill jobs.")
  end
end
