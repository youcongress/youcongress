defmodule YouCongress.Accounts.Permissions do
  @moduledoc """
  The Accounts permissions.
  """
  alias YouCongress.Accounts.User
  alias YouCongress.Votings.Voting

  @doc """
  Checks if the user can edit the given voting.
  """
  @spec can_edit_voting?(Voting.t(), User.t()) :: boolean()
  def can_edit_voting?(_voting, %User{role: "admin"}), do: true
  def can_edit_voting?(_, _), do: false

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
end
