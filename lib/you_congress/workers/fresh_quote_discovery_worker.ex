defmodule YouCongress.Workers.FreshQuoteDiscoveryWorker do
  @moduledoc """
  Starts hourly discovery of fresh sourced quotes about AI and society.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [states: [:scheduled, :available, :executing]]

  require Logger

  alias YouCongress.Opinions.Quotes.FreshQuoteFinder
  alias YouCongress.Workers.FreshQuoteDiscoveryPollingWorker

  @default_limit 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    request =
      if args["trust_request_id"],
        do: YouCongress.Repo.get(YouCongress.TrustNetwork.Request, args["trust_request_id"])

    with user_id when not is_nil(user_id) <- system_user_id(),
         recent_quotes <- FreshQuoteFinder.recent_quote_inventory(),
         statements <- FreshQuoteFinder.statement_inventory(),
         {:ok, job_id} <-
           FreshQuoteFinder.find_quote(recent_quotes,
             limit: discovery_limit(args),
             statements: statements,
             now: DateTime.utc_now(),
             review_request: request_context(request)
           ) do
      %{
        "job_id" => job_id,
        "user_id" => user_id,
        "limit" => discovery_limit(args),
        "trust_request_id" => request && request.id
      }
      |> FreshQuoteDiscoveryPollingWorker.new()
      |> Oban.insert()

      if request do
        request
        |> Ecto.Changeset.change(
          status: "reviewing",
          attempts:
            request.attempts ++
              [
                %{
                  "at" => DateTime.to_iso8601(DateTime.utc_now()),
                  "result" => "Search started",
                  "job_id" => job_id
                }
              ]
        )
        |> YouCongress.Repo.update!()
      end

      :ok
    else
      nil ->
        Logger.info(
          "Fresh quote discovery skipped because verification_user_id is not configured"
        )

        :ok

      {:error, reason} ->
        Logger.error("Fresh quote discovery failed to start: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp discovery_limit(args) when is_map(args) do
    case Map.get(args, "limit") || Map.get(args, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_limit)
      _ -> @default_limit
    end
  end

  defp discovery_limit(_args), do: @default_limit

  defp system_user_id do
    case Application.get_env(:you_congress, :verification_user_id) do
      nil -> nil
      "" -> nil
      id when is_integer(id) -> id
      id when is_binary(id) -> normalize_id(id)
    end
  end

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp request_context(nil), do: nil

  defp request_context(request) do
    author =
      request.author_id && YouCongress.Repo.get(YouCongress.Authors.Author, request.author_id)

    %{
      kind: request.kind,
      body: request.body,
      source_url: request.source_url,
      author: author && author.name,
      statement_id: request.statement_id
    }
  end
end
