defmodule YouCongress.InvitationsTest do
  use YouCongress.DataCase

  alias YouCongress.Invitations

  describe "invitations" do
    alias YouCongress.Invitations.Invitation

    import YouCongress.InvitationsFixtures

    @invalid_attrs %{twitter_username: nil}

    test "list_invitations/0 returns all invitations" do
      invitation = invitation_fixture()
      assert Invitations.list_invitations() == [invitation]
    end

    test "get_invitation!/1 returns the invitation with given id" do
      invitation = invitation_fixture()
      assert Invitations.get_invitation!(invitation.id) == invitation
    end

    test "create_invitation/1 with valid data creates a invitation" do
      valid_attrs = %{twitter_username: "some twitter_username"}

      assert {:ok, %Invitation{} = invitation} = Invitations.create_invitation(valid_attrs)
      assert invitation.twitter_username == "some twitter_username"
    end

    test "create_invitation/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Invitations.create_invitation(@invalid_attrs)
    end

    test "update_invitation/2 with valid data updates the invitation" do
      invitation = invitation_fixture()
      update_attrs = %{twitter_username: "some updated twitter_username"}

      assert {:ok, %Invitation{} = invitation} =
               Invitations.update_invitation(invitation, update_attrs)

      assert invitation.twitter_username == "some updated twitter_username"
    end

    test "update_invitation/2 with invalid data returns error changeset" do
      invitation = invitation_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Invitations.update_invitation(invitation, @invalid_attrs)

      assert invitation == Invitations.get_invitation!(invitation.id)
    end

    test "delete_invitation/1 deletes the invitation" do
      invitation = invitation_fixture()
      assert {:ok, %Invitation{}} = Invitations.delete_invitation(invitation)
      assert_raise Ecto.NoResultsError, fn -> Invitations.get_invitation!(invitation.id) end
    end

    test "change_invitation/1 returns a invitation changeset" do
      invitation = invitation_fixture()
      assert %Ecto.Changeset{} = Invitations.change_invitation(invitation)
    end
  end
end
