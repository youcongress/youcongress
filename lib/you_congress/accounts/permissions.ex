defmodule YouCongress.Accounts.Permissions do
  @moduledoc """
  The Accounts permissions.
  """
  alias YouCongress.Accounts.User
  alias YouCongress.Statements.Statement

  def can_create_statement?(%User{role: "admin"}), do: true
  def can_create_statement?(%User{role: "creator"}), do: true
  def can_create_statement?(_), do: false

  @doc """
  Checks if the user can edit the given statement.
  """
  @spec can_edit_statement?(Statement.t(), User.t()) :: boolean()
  def can_edit_statement?(_statement, %User{role: "admin"}), do: true
  def can_edit_statement?(_, _), do: false

  @doc """
  Checks if the user can generate AI votes
  """
  @spec can_generate_ai_votes?(User.t()) :: boolean()
  def can_generate_ai_votes?(%User{role: "creator"}), do: true
  def can_generate_ai_votes?(%User{role: "admin"}), do: true
  def can_generate_ai_votes?(_), do: false

  @doc """
  Checks if the user can create authors
  """
  def can_create_authors?(%User{role: "admin"}), do: true
  def can_create_authors?(_), do: false

  @doc """
  Checks if the user can edit the given author.
  """
  def can_edit_author?(%User{role: "admin"}), do: true
  def can_edit_author?(_), do: false

  def can_regenerate_opinion?(%User{role: "admin"}), do: true
  def can_regenerate_opinion?(%User{role: "moderator"}), do: true
  def can_regenerate_opinion?(_), do: false

  @doc """
  Checks if the user can add an opinion to a statement.
  """
  def can_add_opinion_to_statement?(%User{role: "admin"}), do: true
  def can_add_opinion_to_statement?(%User{role: "moderator"}), do: true
  def can_add_opinion_to_statement?(_), do: false

  @doc """
  Checks if the user can edit the given opinion.
  """
  def can_edit_opinion?(%{user_id: id}, %User{id: id}), do: true
  def can_edit_opinion?(_opinion, %User{role: "admin"}), do: true
  def can_edit_opinion?(_opinion, %User{role: "moderator"}), do: true
  def can_edit_opinion?(_opinion, _user), do: false

  def can_verify_opinion?(%User{role: "admin"}), do: true
  def can_verify_opinion?(%User{role: "moderator"}), do: true
  def can_verify_opinion?(_), do: false

  @doc """
  Checks if a user has a blocked role (spam or blocked).
  """
  @spec blocked?(User.t() | nil) :: boolean()
  def blocked?(%User{role: role}) when role in ["spam", "blocked"], do: true
  def blocked?(_), do: false
end
