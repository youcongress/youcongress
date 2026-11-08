defmodule YouCongress.CouncilInvitationsTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import Swoosh.TestAssertions
  alias YouCongress.{Councils, Repo}
  alias YouCongress.Councils.{Invitations, Invitation}

  test "invitations deliver once, and their history belongs to the sender" do
    user = user_fixture()
    other = user_fixture()

    assert {:ok, 1} =
             Invitations.send(
               user,
               "friend@example.com, FRIEND@example.com",
               "Would love to see your picks."
             )

    assert_email_sent(to: "friend@example.com")
    assert [%{status: "sent"}] = Invitations.history(user)
    assert Invitations.history(other) == []
    assert {:ok, 0} = Invitations.send(user, "friend@example.com", "Again")
    refute_email_sent(to: "friend@example.com")
  end

  test "invalid addresses and notes cannot queue a batch" do
    user = user_fixture()
    assert {:error, :invalid_emails} = Invitations.send(user, "good@example.com, invalid", "Hi")
    assert Invitations.history(user) == []

    assert {:error, :invalid_emails} =
             Invitations.send(user, "good@example.com", String.duplicate("x", 2001))

    assert Invitations.history(user) == []
  end

  test "twenty-per-day limit is enforced" do
    user = user_fixture()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(
      Invitation,
      for(
        n <- 1..20,
        do: %{
          user_id: user.id,
          email: "friend#{n}@example.com",
          status: "sent",
          inserted_at: now,
          updated_at: now
        }
      )
    )

    assert {:error, :rate_limited} = Invitations.send(user, "another@example.com", "Hi")
    assert length(Invitations.history(user)) == 20
  end

  test "referrals are signed, do not reveal private Councils, and cannot be reassigned" do
    inviter = user_fixture()
    other = user_fixture()
    user = user_fixture()
    token = Invitations.token(inviter.author_id)
    assert Invitations.referrer(token).id == inviter.author_id
    assert Invitations.referrer(token <> "tampered") == nil
    assert :ok = Invitations.accept(user, token)
    assert Councils.get(user.author_id).invited_by_id == inviter.author_id
    assert :ok = Invitations.accept(user, Invitations.token(other.author_id))
    assert Councils.get(user.author_id).invited_by_id == inviter.author_id
    assert Invitations.joined(inviter.author_id) == 1
    assert Councils.public(inviter.author_id) == nil
  end
end
