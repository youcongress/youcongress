defmodule YouCongress.Workers.NewUserSignupNotificationWorker do
  @moduledoc """
  Delivers the internal notification for a newly created YouCongress account.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 5

  alias YouCongress.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"name" => name, "email" => email}}) do
    case UserNotifier.deliver_new_user_signup_notification(name, email) do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
