defmodule YouCongress.Newsletters do
  @moduledoc """
  Newsletter consent boundary. Anonymous requests remain pending until their
  one-time email token is consumed; authenticated changes are recorded as
  confirmed append-only events immediately.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias YouCongress.Accounts
  alias YouCongress.Accounts.User
  alias YouCongress.Newsletters.NewsletterConsent
  alias YouCongress.Repo
  alias YouCongress.Workers.NewsletterConfirmationWorker

  @confirmation_validity_seconds 24 * 60 * 60

  def change_request(attrs \\ %{}) do
    {%{}, %{email: :string}}
    |> cast(attrs, [:email])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
  end

  def request_subscription(attrs, source) when is_binary(source) do
    changeset = change_request(attrs)

    if changeset.valid? do
      email = get_change(changeset, :email)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      consent_attrs = %{
        email: email,
        action: :subscribe,
        source: source,
        expires_at: DateTime.add(now, @confirmation_validity_seconds, :second)
      }

      Repo.transaction(fn ->
        from(consent in NewsletterConsent,
          where:
            consent.email == ^email and consent.action == :subscribe and
              is_nil(consent.confirmed_at) and not is_nil(consent.token_hash)
        )
        |> Repo.update_all(set: [token_hash: nil, expires_at: now])

        consent = Repo.insert!(NewsletterConsent.changeset(%NewsletterConsent{}, consent_attrs))

        %{"consent_id" => consent.id}
        |> NewsletterConfirmationWorker.new()
        |> Oban.insert!()

        consent
      end)
    else
      {:error, changeset}
    end
  end

  @doc false
  def prepare_confirmation_delivery(consent_id) when is_integer(consent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      consent =
        from(consent in NewsletterConsent,
          where:
            consent.id == ^consent_id and consent.action == :subscribe and
              is_nil(consent.confirmed_at) and consent.expires_at > ^now,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case consent do
        %NewsletterConsent{} ->
          token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
          Repo.update!(change(consent, token_hash: hash_token(token)))
          {consent.email, token}

        nil ->
          Repo.rollback(:expired_or_superseded)
      end
    end)
  end

  def confirm_subscription(token) when is_binary(token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      consent =
        from(consent in NewsletterConsent,
          where:
            consent.token_hash == ^hash_token(token) and consent.action == :subscribe and
              is_nil(consent.confirmed_at) and consent.expires_at > ^now,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case consent do
        %NewsletterConsent{} ->
          user = Accounts.get_user_by_email(consent.email)

          consent =
            Repo.update!(
              change(consent,
                confirmed_at: now,
                token_hash: nil,
                user_id: user && user.id
              )
            )

          maybe_update_user_subscription(user, true)
          consent

        nil ->
          Repo.rollback(:invalid_or_expired_token)
      end
    end)
  end

  def confirm_subscription(_token), do: {:error, :invalid_or_expired_token}

  def subscribe_user(%User{} = user, source), do: set_user_subscription(user, true, source)
  def unsubscribe_user(%User{} = user, source), do: set_user_subscription(user, false, source)

  def latest_consent(email) when is_binary(email) do
    from(consent in NewsletterConsent,
      where: consent.email == ^normalize_email(email) and not is_nil(consent.confirmed_at),
      order_by: [desc: consent.confirmed_at, desc: consent.id],
      limit: 1
    )
    |> Repo.one()
  end

  defp set_user_subscription(user, subscribed?, source) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    action = if subscribed?, do: :subscribe, else: :unsubscribe

    Repo.transaction(fn ->
      current_user =
        from(stored_user in User, where: stored_user.id == ^user.id, lock: "FOR UPDATE")
        |> Repo.one!()

      attrs = %{newsletter: subscribed?}

      attrs =
        if subscribed?,
          do: attrs,
          else:
            Map.put(
              attrs,
              :newsletter_subscription_prompt_dismissed_at,
              NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            )

      updated_user = current_user |> change(attrs) |> Repo.update!()

      unless match?(%NewsletterConsent{action: ^action}, latest_consent(updated_user.email)) do
        %NewsletterConsent{}
        |> NewsletterConsent.changeset(%{
          email: updated_user.email,
          action: action,
          source: source,
          confirmed_at: now,
          user_id: updated_user.id
        })
        |> Repo.insert!()
      end

      updated_user
    end)
  end

  defp maybe_update_user_subscription(%User{} = user, subscribed?),
    do: user |> change(newsletter: subscribed?) |> Repo.update!()

  defp maybe_update_user_subscription(nil, _subscribed?), do: :ok

  defp normalize_email(email), do: email |> String.trim() |> User.normalize_email()
  defp hash_token(token), do: :crypto.hash(:sha256, token)
end
