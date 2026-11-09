defmodule YouCongress.Councils.Invitations do
  @moduledoc "Opt-in Council invitations, private delivery history, and author-ID referrals."
  import Ecto.Query
  alias YouCongress.{Repo, Councils}
  alias YouCongress.Accounts.{User, Permissions}
  alias YouCongress.Councils.{Council, Invitation}
  alias YouCongressWeb.Endpoint

  def url(author_id),
    do: Endpoint.url() <> "/council?" <> URI.encode_query(%{ref: author_id})

  def referrer(ref) when is_binary(ref) do
    with {:ok, id} <- referral_id(ref),
         %User{} = user <- Repo.get_by(User, author_id: id),
         false <- Permissions.blocked?(user) do
      Repo.get(YouCongress.Authors.Author, id)
    else
      _ -> nil
    end
  end

  def referrer(_), do: nil

  defp referral_id(ref) do
    case Integer.parse(ref) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> {:ok, id}
      # Previously shared token links continue to work.
      _ -> Phoenix.Token.verify(Endpoint, "council-invite", ref, max_age: 31_536_000)
    end
  end

  def accept(user, ref) do
    case referrer(ref) do
      %{id: id} when id != user.author_id ->
        {:ok, council} = Councils.ensure(user.author_id)

        Repo.update_all(
          from(c in Council, where: c.id == ^council.id and is_nil(c.invited_by_id)),
          set: [invited_by_id: id]
        )

        :ok

      _ ->
        :ok
    end
  end

  def history(%User{id: id}) do
    Repo.all(from i in Invitation, where: i.user_id == ^id, order_by: [desc: i.id], limit: 20)
  end

  def joined(author_id),
    do: Repo.aggregate(from(c in Council, where: c.invited_by_id == ^author_id), :count)

  def send(%User{} = user, raw_emails, note) when is_binary(raw_emails) and is_binary(note) do
    emails =
      raw_emails
      |> String.split(~r/[,;\s]+/, trim: true)
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    cond do
      Permissions.blocked?(user) or is_nil(user.email_confirmed_at) ->
        {:error, :forbidden}

      emails == [] or length(emails) > 10 ->
        {:error, :invalid_emails}

      Enum.any?(
        emails,
        &(not Invitation.changeset(%Invitation{}, %{user_id: user.id, email: &1, note: note}).valid?)
      ) ->
        {:error, :invalid_emails}

      true ->
        queue(user, emails, note)
    end
  end

  def send(_, _, _), do: {:error, :invalid_emails}

  defp queue(user, emails, note) do
    Repo.transaction(fn ->
      Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")
      since = NaiveDateTime.utc_now() |> NaiveDateTime.add(-86_400)

      recent =
        Repo.aggregate(
          from(i in Invitation, where: i.user_id == ^user.id and i.inserted_at > ^since),
          :count
        )

      existing =
        Repo.all(
          from i in Invitation,
            where: i.user_id == ^user.id and i.email in ^emails,
            select: i.email
        )

      fresh = emails -- existing
      if recent + length(fresh) > 20, do: Repo.rollback(:rate_limited)

      Enum.each(fresh, fn email ->
        changeset =
          Invitation.changeset(%Invitation{}, %{user_id: user.id, email: email, note: note})

        case Repo.insert(changeset) do
          {:ok, invitation} ->
            %{invitation_id: invitation.id}
            |> YouCongress.Workers.CouncilInvitationWorker.new()
            |> Oban.insert!()

          {:error, _} ->
            Repo.rollback(:invalid_emails)
        end
      end)

      length(fresh)
    end)
  end
end
