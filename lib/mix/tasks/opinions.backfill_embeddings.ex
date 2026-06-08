defmodule Mix.Tasks.Opinions.BackfillEmbeddings do
  @moduledoc """
  Enqueues an Oban job to backfill the missing embedding of each sourced quote.

  ## Options

    * `--limit` - maximum number of quotes to enqueue
  """

  use Mix.Task

  import Ecto.Query

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo
  alias YouCongress.Workers.BackfillOpinionEmbeddingWorker

  @shortdoc "Enqueues sourced quote embedding backfill jobs"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [limit: :integer])

    limit = normalize_limit(Keyword.get(opts, :limit))

    enqueued =
      opinion_ids(limit)
      |> Enum.reduce(0, fn opinion_id, count ->
        case %{opinion_id: opinion_id} |> BackfillOpinionEmbeddingWorker.new() |> Oban.insert() do
          {:ok, _job} -> count + 1
          {:error, _reason} -> count
        end
      end)

    Mix.shell().info("Enqueued #{enqueued} embedding backfill jobs.")
  end

  defp opinion_ids(limit) do
    query =
      from(o in Opinion,
        where: not is_nil(o.source_url) and is_nil(o.content_embedding),
        order_by: [asc: o.id],
        select: o.id
      )

    query = if is_integer(limit), do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  defp normalize_limit(nil), do: nil
  defp normalize_limit(limit), do: max(limit, 0)
end
