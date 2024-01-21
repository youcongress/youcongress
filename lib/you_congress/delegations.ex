defmodule YouCongress.Delegations do
  @moduledoc """
  The Delegations context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Delegations.Delegation
  alias YouCongress.DelegationVotes

  @doc """
  Returns the list of delegations.

  ## Examples

      iex> list_delegations()
      [%Delegation{}, ...]

  """
  def list_delegations do
    Repo.all(Delegation)
  end

  def delegate_ids_by_author_id(author_id) do
    Repo.all(from d in Delegation, where: d.deleguee_id == ^author_id, select: d.delegate_id)
  end

  def deleguee_ids_by_delegate_id(delegate_id) do
    Repo.all(from d in Delegation, where: d.delegate_id == ^delegate_id, select: d.deleguee_id)
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
    result =
      %Delegation{}
      |> Delegation.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, delegation} ->
        DelegationVotes.update_author_delegated_votes(delegation.deleguee_id)

        {:ok, delegation}

      {:error, changeset} ->
        {:error, changeset}
    end
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
    result =
      Repo.get_by(Delegation, deleguee_id: deleguee_id, delegate_id: delegate_id)
      |> Repo.delete()

    case result do
      {:ok, delegation} ->
        DelegationVotes.update_author_delegated_votes(deleguee_id)
        {:ok, delegation}

      {:error, changeset} ->
        {:error, changeset}
    end
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
