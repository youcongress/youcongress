defmodule YouCongress.InvitationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Invitations` context.
  """

  @doc """
  Generate a invitation.
  """
  def invitation_fixture(attrs \\ %{}) do
    {:ok, invitation} =
      attrs
      |> Enum.into(%{
        twitter_username: "some twitter_username"
      })
      |> YouCongress.Invitations.create_invitation()

    invitation
  end
end
