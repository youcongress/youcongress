defmodule YouCongress.Workers.TrustDigestWorker do
  @moduledoc "Opt-in daily/weekly notification digests; preference is checked again at delivery."
  use Oban.Worker, queue: :mailers, unique: [period: 86_400, keys: [:author_id, :date]]
  import Ecto.Query
  import Swoosh.Email, except: [from: 2]
  alias YouCongress.{Repo, Mailer}
  alias YouCongress.Councils.Council
  alias YouCongress.TrustNetwork.Notification

  @impl true
  def perform(%Oban.Job{args: %{"author_id" => id}}) do
    Repo.transaction(fn ->
      council = Repo.one(from c in Council, where: c.author_id == ^id, lock: "FOR UPDATE")

      user =
        Repo.one(
          from u in YouCongress.Accounts.User,
            where: u.author_id == ^id and u.role not in ["spam", "blocked"],
            limit: 1
        )

      if eligible?(council, user), do: deliver(user)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp eligible?(%Council{digest: digest}, %{email: email, email_confirmed_at: confirmed}) do
    digest in ["daily", "weekly"] and is_binary(email) and not is_nil(confirmed)
  end

  defp eligible?(_, _), do: false

  defp deliver(user) do
    notifications =
      Repo.all(
        from n in Notification,
          where: n.author_id == ^user.author_id and is_nil(n.emailed_at) and is_nil(n.read_at),
          order_by: n.id,
          limit: 100
      )

    if notifications != [], do: deliver_notifications(user, notifications)
  end

  defp deliver_notifications(user, notifications) do
    base = YouCongressWeb.Endpoint.url()
    token = Phoenix.Token.sign(YouCongressWeb.Endpoint, "trust-digest", user.author_id)
    unsubscribe = base <> "/trust/unsubscribe/" <> token
    body = Enum.map_join(notifications, "\n\n", &(&1.body <> "\n" <> base <> &1.path))

    email =
      new()
      |> to(user.email)
      |> Swoosh.Email.from({"YouCongress", "hello@youcongress.org"})
      |> subject("Your YouCongress updates")
      |> text_body(body <> "\n\nTurn off email updates: " <> unsubscribe)
      |> header("List-Unsubscribe", "<#{unsubscribe}>")

    case Mailer.deliver(email) do
      {:ok, _} ->
        ids = Enum.map(notifications, & &1.id)

        Repo.update_all(from(n in Notification, where: n.id in ^ids),
          set: [emailed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)]
        )

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end
end
