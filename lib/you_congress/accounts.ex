defmodule YouCongress.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Accounts.{User, UserToken, UserNotifier}
  alias YouCongress.Authors.Author

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by username.

  ## Examples

      iex> get_user_by_username("foo")
      %User{}

      iex> get_user_by_username("unknown")
      nil

  """
  def get_user_by_username(username) when is_binary(username) do
    query =
      from u in User,
        join: a in Author,
        on: u.author_id == a.id,
        where: a.twitter_username == ^username,
        select: u,
        preload: [author: a]

    Repo.one(query)
  end

  @doc """
  Gets a user by twitter id or username.

  ## Examples

      iex> get_user_by_twitter_id_or_username("123", "foo")
      %User{}

      iex> get_user_by_twitter_id_or_username("123", "unknown")
      nil

  """
  def get_user_by_twitter_id_str_or_username(nil, twitter_username),
    do: get_user_by_username(twitter_username)

  def get_user_by_twitter_id_str_or_username(twitter_id_str, twitter_username) do
    query =
      from u in User,
        join: a in Author,
        on: u.author_id == a.id,
        where: a.twitter_id_str == ^twitter_id_str,
        select: u,
        preload: [author: a]

    Repo.one(query) || get_user_by_username(twitter_username)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  def get_user!(id, include: tables) do
    Repo.get!(User, id) |> Repo.preload(tables)
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(user_attrs, author_attrs \\ %{}) do
    author_attrs = Map.put(author_attrs, "twin_origin", false)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:author, Author.changeset(%Author{}, author_attrs))
    |> Ecto.Multi.insert(:user, fn %{author: author} ->
      User.password_registration_changeset(%User{}, Map.put(user_attrs, "author_id", author.id))
    end)
    |> Repo.transaction()
  end

  def x_register_user(user_attrs, author_attrs \\ %{}) do
    author_attrs = Map.put(author_attrs, :twin_origin, false)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:author, Author.changeset(%Author{}, author_attrs))
    |> Ecto.Multi.insert(:user, fn %{author: author} ->
      User.twitter_registration_changeset(%User{}, Map.put(user_attrs, "author_id", author.id))
    end)
    |> Repo.transaction()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.password_registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  def change_user_phone_number(user, attrs \\ %{}) do
    User.phone_number_changeset(user, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  def update_user_phone_number(user, phone_number) do
    user
    |> User.phone_number_changeset(%{"phone_number" => phone_number})
    |> Repo.update()
  end

  def update_login_with_x(%User{} = user, attrs) do
    user
    |> User.login_with_x_changeset(attrs)
    |> Repo.update()
  end

  def welcome_update(%User{} = user, attrs) do
    user
    |> User.welcome_changeset(attrs)
    |> Repo.update()
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/settings/confirm_email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    Repo.one(query)
    |> Repo.preload(:author)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def update_role(user, role) do
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
  end

  def admin?(%User{role: "admin"}), do: true
  def admin?(_), do: false

  def in_waiting_list?(%User{role: "waiting_list"}), do: true
  def in_waiting_list?(_), do: false

  def count, do: Repo.aggregate(User, :count, :id)

  @doc """
  Confirms a user's email.

  ## Examples

      iex> confirm_user_email(user)
      {:ok, %User{}}

      iex> confirm_user_email(invalid_user)
      {:error, %Ecto.Changeset{}}

  """
  def confirm_user_email(%User{} = user) do
    changeset = User.email_confirm_changeset(user)
    Repo.update(changeset)
  end

  @doc """
  Confirms a user's phone number.

  ## Examples

      iex> confirm_user_phone(user)
      {:ok, %User{}}

      iex> confirm_user_phone(invalid_user)
      {:error, %Ecto.Changeset{}}

  """
  def confirm_user_phone(%User{} = user) do
    changeset = User.phone_number_confirm_changeset(user)
    Repo.update(changeset)
  end
end
