defmodule YouCongress.DelegationsTest do
  use YouCongress.DataCase

  describe "delegations" do
    import YouCongress.DelegationsFixtures

    alias YouCongress.Delegations
    alias YouCongress.Delegations.Delegation
    alias YouCongress.AuthorsFixtures

    @invalid_attrs %{delegate_id: nil, deleguee_id: nil}

    test "create_delegation/1 with valid data creates a delegation" do
      delegate_id = AuthorsFixtures.author_fixture().id
      deleguee_id = AuthorsFixtures.author_fixture().id

      valid_attrs = %{delegate_id: delegate_id, deleguee_id: deleguee_id}

      assert {:ok, %Delegation{delegate_id: ^delegate_id, deleguee_id: ^deleguee_id}} =
               Delegations.create_delegation(valid_attrs)
    end

    test "create_delegation/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Delegations.create_delegation(@invalid_attrs)
    end

    test "delete_delegation/1 deletes the delegation" do
      delegation = delegation_fixture()
      assert {:ok, %Delegation{}} = Delegations.delete_delegation(delegation)
      refute YouCongress.Repo.get(Delegation, delegation.id)
      refute Delegations.delegating?(delegation.deleguee_id, delegation.delegate_id)
      refute delegation.delegate_id in YouCongress.Councils.delegate_ids(delegation.deleguee_id)
    end
  end
end
