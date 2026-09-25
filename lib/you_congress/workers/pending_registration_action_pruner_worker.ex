defmodule YouCongress.Workers.PendingRegistrationActionPrunerWorker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query, warn: false

  alias YouCongress.PendingActions.PendingRegistrationAction
  alias YouCongress.Repo

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    Repo.delete_all(from(action in PendingRegistrationAction, where: action.expires_at <= ^now))
    :ok
  end
end
