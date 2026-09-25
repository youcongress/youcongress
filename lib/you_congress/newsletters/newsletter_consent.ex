defmodule YouCongress.Newsletters.NewsletterConsent do
  @moduledoc "Append-only newsletter consent and revocation record."

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Accounts.User

  schema "newsletter_consents" do
    field :email, :string
    field :action, Ecto.Enum, values: [:subscribe, :unsubscribe]
    field :source, :string
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :confirmed_at, :utc_datetime
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [
      :email,
      :action,
      :source,
      :token_hash,
      :expires_at,
      :confirmed_at,
      :user_id
    ])
    |> validate_required([:email, :action, :source])
    |> validate_length(:email, max: 160)
    |> validate_length(:source, max: 100)
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
  end
end
