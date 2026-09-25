defmodule YouCongress.Workers.AccountEmailWorker do
  @moduledoc """
  Delivers account emails outside the request process. Jobs are enqueued for
  both known and unknown addresses so public endpoints have the same observable
  database/queue behavior without revealing account existence.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 5
  use YouCongressWeb, :verified_routes

  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongressWeb.ReturnTo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind, "email" => email} = args}) do
    with user when not is_nil(user) <- Accounts.get_user_by_email(email),
         false <- Permissions.blocked?(user) do
      deliver(kind, user, ReturnTo.sanitize(args["return_to"]))
    else
      _ -> :ok
    end
  end

  defp deliver("magic_login", user, return_to) do
    Accounts.deliver_user_magic_login_instructions(user, fn token ->
      url(~p"/log_in/magic-link/#{token}?#{return_to_query(return_to)}")
    end)
  end

  defp deliver("registration", user, return_to) do
    Accounts.deliver_user_registration_magic_link_instructions(
      user,
      fn token ->
        url(~p"/log_in/magic-link/#{token}?#{return_to_query(return_to)}")
      end,
      results_url: reconsider_results_url(return_to)
    )
  end

  defp deliver("password_reset", user, _return_to) do
    Accounts.deliver_user_reset_password_instructions(
      user,
      &url(~p"/reset_password/#{&1}")
    )
  end

  defp deliver(_kind, _user, _return_to), do: :discard

  defp return_to_query(nil), do: %{}
  defp return_to_query(return_to), do: %{return_to: return_to}

  defp reconsider_results_url(return_to) when is_binary(return_to) do
    with %URI{path: path} <- URI.parse(return_to),
         ["@" <> username, "r", slug] <- String.split(path, "/", trim: true),
         true <- username != "" and slug != "" do
      YouCongressWeb.Endpoint.url() <> return_to
    else
      _ -> nil
    end
  end

  defp reconsider_results_url(_return_to), do: nil
end
