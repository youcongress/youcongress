defmodule YouCongress.Workers.ReconsiderationCreatedNotificationWorker do
  @moduledoc """
  Delivers the internal notification for a newly created Reconsider page.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 5

  alias YouCongress.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"creator_name" => creator_name, "reconsideration_url" => url}}) do
    case UserNotifier.deliver_reconsideration_created_notification(creator_name, url) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
