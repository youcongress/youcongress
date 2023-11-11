defmodule YouCongress.DelegationsTest do
  use YouCongress.DataCase

  describe "delegations" do
    import YouCongress.DelegationsFixtures

    alias YouCongress.Delegations
    alias YouCongress.Delegations.Delegation
    alias YouCongress.AuthorsFixtures

    @invalid_attrs %{delegate_id: nil, deleguee_id: nil}

    test "list_delegations/0 returns all delegations" do
      delegation = delegation_fixture()
      assert Delegations.list_delegations() == [delegation]
    end

    test "get_delegation!/1 returns the delegation with given id" do
      delegation = delegation_fixture()
      assert Delegations.get_delegation!(delegation.id) == delegation
    end

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

    test "update_delegation/2 with valid data updates the delegation" do
      delegation = delegation_fixture()
      update_attrs = %{}

      assert {:ok, %Delegation{}} = Delegations.update_delegation(delegation, update_attrs)
    end

    test "update_delegation/2 with invalid data returns error changeset" do
      delegation = delegation_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Delegations.update_delegation(delegation, @invalid_attrs)

      assert delegation == Delegations.get_delegation!(delegation.id)
    end

    test "delete_delegation/1 deletes the delegation" do
      delegation = delegation_fixture()
      assert {:ok, %Delegation{}} = Delegations.delete_delegation(delegation)
      assert_raise Ecto.NoResultsError, fn -> Delegations.get_delegation!(delegation.id) end
    end

    test "change_delegation/1 returns a delegation changeset" do
      delegation = delegation_fixture()
      assert %Ecto.Changeset{} = Delegations.change_delegation(delegation)
    end
  end
end
