defmodule YouCongress.Workers.TrustDailyWorker do
  @moduledoc "Queues opt-in digests and bounded evidence discovery once per day."
  use Oban.Worker, unique: [period: 86_400]
  import Ecto.Query
  alias YouCongress.Repo
  alias YouCongress.Councils.Council
  alias YouCongress.TrustNetwork.Request

  @impl true
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    weekly = Date.day_of_week(today) == 1

    councils =
      Repo.all(
        from c in Council, where: c.digest == "daily" or (c.digest == "weekly" and ^weekly)
      )

    Enum.each(councils, fn c ->
      %{author_id: c.author_id, date: Date.to_iso8601(today)}
      |> YouCongress.Workers.TrustDigestWorker.new()
      |> Oban.insert()
    end)

    if Application.get_env(:you_congress, :verification_user_id) do
      request =
        Repo.one(
          from r in Request,
            where: r.status == "open" and r.kind != "missing_person",
            order_by: [asc: r.inserted_at],
            limit: 1
        )

      args = if request, do: %{trust_request_id: request.id}, else: %{}
      args |> YouCongress.Workers.FreshQuoteDiscoveryWorker.new() |> Oban.insert()
    end

    :ok
  end
end
