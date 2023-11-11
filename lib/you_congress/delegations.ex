defmodule YouCongress.Delegations do
  @moduledoc """
  The Delegations context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Delegations.Delegation

  @doc """
  Returns the list of delegations.

  ## Examples

      iex> list_delegations()
      [%Delegation{}, ...]

  """
  def list_delegations do
    Repo.all(Delegation)
  end

  @doc """
  Gets a single delegation.

  Raises `Ecto.NoResultsError` if the Delegation does not exist.

  ## Examples

      iex> get_delegation!(123)
      %Delegation{}

      iex> get_delegation!(456)
      ** (Ecto.NoResultsError)

  """
  def get_delegation!(id), do: Repo.get!(Delegation, id)

  @doc """
  Creates a delegation.

  ## Examples

      iex> create_delegation(%{field: value})
      {:ok, %Delegation{}}

      iex> create_delegation(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_delegation(attrs \\ %{}) do
    %Delegation{}
    |> Delegation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a delegation.

  ## Examples

      iex> update_delegation(delegation, %{field: new_value})
      {:ok, %Delegation{}}

      iex> update_delegation(delegation, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_delegation(%Delegation{} = delegation, attrs) do
    delegation
    |> Delegation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a delegation.

  ## Examples

      iex> delete_delegation(%{deleguee_id: 1, delegate_id: 2})
      {:ok, %Delegation{}}

      iex> delete_delegation(%{deleguee_id: 3, delegate_id: 4})
      {:error, %Ecto.Changeset{}}
  """

  def delete_delegation(%{deleguee_id: deleguee_id, delegate_id: delegate_id}) do
    Repo.get_by(Delegation, deleguee_id: deleguee_id, delegate_id: delegate_id)
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking delegation changes.

  ## Examples

      iex> change_delegation(delegation)
      %Ecto.Changeset{data: %Delegation{}}

  """
  def change_delegation(%Delegation{} = delegation, attrs \\ %{}) do
    Delegation.changeset(delegation, attrs)
  end

  @doc """
  Returns true if the deleguee has delegated to the delegate.
  """
  def delegating?(deleguee_id, delegate_id) do
    !!Repo.get_by(Delegation, deleguee_id: deleguee_id, delegate_id: delegate_id)
  end
end
