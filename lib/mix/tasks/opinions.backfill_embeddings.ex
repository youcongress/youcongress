defmodule Mix.Tasks.Opinions.BackfillEmbeddings do
  @moduledoc """
  Backfills missing embeddings for sourced quotes.

  ## Options

    * `--batch-size` - number of quotes to process per batch, defaults to 50
    * `--limit` - maximum number of quotes to inspect
  """

  use Mix.Task

  import Ecto.Query

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo

  @shortdoc "Backfills sourced quote content embeddings"
  @default_batch_size 50

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [batch_size: :integer, limit: :integer])

    batch_size = opts |> Keyword.get(:batch_size, @default_batch_size) |> max(1)
    limit = normalize_limit(Keyword.get(opts, :limit))

    %{seen: seen, updated: updated} = backfill(batch_size, limit, 0, 0, 0)

    Mix.shell().info("Inspected #{seen} sourced quotes; backfilled #{updated} embeddings.")
  end

  defp backfill(_batch_size, limit, _last_id, seen, updated)
       when is_integer(limit) and seen >= limit do
    %{seen: seen, updated: updated}
  end

  defp backfill(batch_size, limit, last_id, seen, updated) do
    remaining = if is_integer(limit), do: limit - seen, else: batch_size
    current_batch_size = min(batch_size, remaining)

    opinions =
      from(o in Opinion,
        where: o.id > ^last_id and not is_nil(o.source_url) and is_nil(o.content_embedding),
        order_by: [asc: o.id],
        limit: ^current_batch_size
      )
      |> Repo.all()

    case opinions do
      [] ->
        %{seen: seen, updated: updated}

      opinions ->
        updated_in_batch =
          Enum.count(opinions, fn opinion ->
            try do
              {:ok, updated_opinion} =
                Opinions.update_opinion(opinion, %{content: opinion.content})

              not is_nil(updated_opinion.content_embedding)
            rescue
              _ -> false
            end
          end)

        backfill(
          batch_size,
          limit,
          List.last(opinions).id,
          seen + length(opinions),
          updated + updated_in_batch
        )
    end
  end

  defp normalize_limit(nil), do: nil
  defp normalize_limit(limit), do: max(limit, 0)
end
