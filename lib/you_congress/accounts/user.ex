defmodule YouCongress.Accounts.User do
  @moduledoc """
  The User context.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @user_roles ["user", "creator", "admin"]

  schema "users" do
    field :email, :string
    field :phone_number, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :email_confirmed_at, :naive_datetime
    field :phone_number_confirmed_at, :naive_datetime
    field :role, :string, default: "user"
    field :newsletter, :boolean, default: false

    belongs_to :author, YouCongress.Authors.Author

    timestamps()
  end

  @type t :: %__MODULE__{
          email: String.t(),
          phone_number: String.t() | nil,
          password: String.t() | nil,
          hashed_password: String.t(),
          email_confirmed_at: NaiveDateTime.t() | nil,
          phone_number_confirmed_at: NaiveDateTime.t() | nil,
          role: String.t(),
          author_id: integer() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t(),
          newsletter: boolean()
        }

  def password_registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :author_id])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  def twitter_registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :author_id, :role])
    |> validate_email(opts)
  end

  def welcome_changeset(user, attrs) do
    user
    |> cast(attrs, [:newsletter])
  end

  def login_with_x_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :role])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, YouCongress.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  def phone_number_changeset(user, attrs) do
    user
    |> cast(attrs, [:phone_number])
    |> validate_required([:phone_number])
    |> validate_format(:phone_number, ~r/^\+?[0-9]{10,14}$/,
      message: "must be a valid phone number"
    )
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def email_confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, email_confirmed_at: now)
  end

  def phone_number_confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, phone_number_confirmed_at: now)
  end

  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, @user_roles)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%YouCongress.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end
end
