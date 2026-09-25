defmodule YouCongress.PendingActionsTest do
  use YouCongress.DataCase

  import Ecto.Query
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Delegations
  alias YouCongress.PendingActions
  alias YouCongress.PendingActions.PendingRegistrationAction
  alias YouCongress.Repo
  alias YouCongress.Votes
  alias YouCongress.Workers.PendingRegistrationActionPrunerWorker

  test "defers actions until the user's email is confirmed" do
    user = user_fixture(%{}, nil, false)
    statement = statement_fixture()
    payload = vote_payload(statement.id, "for")

    assert :ok = PendingActions.process(user, payload)
    refute Votes.get_by(%{author_id: user.author_id, statement_id: statement.id})
    assert Repo.get_by(PendingRegistrationAction, user_id: user.id)

    assert {:ok, confirmed_user} = Accounts.confirm_user_email(user)
    assert confirmed_user.email_confirmed_at
    assert Votes.get_by(%{author_id: user.author_id, statement_id: statement.id}).answer == :for
    refute Repo.get_by(PendingRegistrationAction, user_id: user.id)
  end

  test "processing a confirmed user's staged action is idempotent" do
    user = user_fixture(%{}, nil, false)
    statement = statement_fixture()
    payload = vote_payload(statement.id, "against")

    assert :ok = PendingActions.process(user, payload)
    assert {:ok, confirmed_user} = Accounts.confirm_user_email(user)

    vote = Votes.get_by(%{author_id: user.author_id, statement_id: statement.id})
    assert vote.answer == :against
    assert :ok = PendingActions.process_staged(confirmed_user)
    assert Votes.get_by(%{author_id: user.author_id, statement_id: statement.id}).id == vote.id
  end

  test "rolls back all action mutations and retains intent when processing fails" do
    user = user_fixture(%{}, nil, false)
    delegate = author_fixture()
    statement = statement_fixture()

    payload = %{
      "delegate_ids" => [delegate.id],
      "votes" => %{
        to_string(statement.id) => %{
          "statement_id" => statement.id,
          "answer" => "invalid"
        }
      }
    }

    assert :ok = PendingActions.process(user, payload)
    assert {:ok, confirmed_user} = Accounts.confirm_user_email(user)
    assert confirmed_user.email_confirmed_at

    refute Delegations.delegating?(user.author_id, delegate.id)
    refute Votes.get_by(%{author_id: user.author_id, statement_id: statement.id})
    assert Repo.get_by(PendingRegistrationAction, user_id: user.id)
  end

  test "prunes abandoned expired intent" do
    user = user_fixture(%{}, nil, false)
    statement = statement_fixture()

    assert :ok = PendingActions.process(user, vote_payload(statement.id, "for"))

    expired_at = DateTime.add(DateTime.utc_now(), -1, :hour) |> DateTime.truncate(:second)

    from(action in PendingRegistrationAction, where: action.user_id == ^user.id)
    |> Repo.update_all(set: [expires_at: expired_at])

    assert :ok = PendingRegistrationActionPrunerWorker.perform(%Oban.Job{})
    refute Repo.get_by(PendingRegistrationAction, user_id: user.id)
  end

  defp vote_payload(statement_id, answer) do
    %{
      "delegate_ids" => [],
      "votes" => %{
        to_string(statement_id) => %{"statement_id" => statement_id, "answer" => answer}
      }
    }
  end
end
