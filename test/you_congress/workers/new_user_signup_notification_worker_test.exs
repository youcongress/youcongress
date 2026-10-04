defmodule YouCongress.Workers.NewUserSignupNotificationWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import Swoosh.TestAssertions

  alias YouCongress.Accounts
  alias YouCongress.Workers.NewUserSignupNotificationWorker

  test "emails Hector with the new user's name and email" do
    assert :ok =
             NewUserSignupNotificationWorker.perform(%Oban.Job{
               args: %{"name" => "Ada Lovelace", "email" => "ada@example.com"}
             })

    assert_email_sent(fn email ->
      assert email.to == [{"", "hector@youcongress.org"}]
      assert email.subject == "New YouCongress signup"
      assert email.text_body =~ "Name: Ada Lovelace"
      assert email.text_body =~ "Email: ada@example.com"
      assert email.html_body =~ "Name: Ada Lovelace"
      assert email.html_body =~ "Email: ada@example.com"
    end)
  end

  test "queues the notification after an X user provides their profile details" do
    {:ok, %{user: user}} =
      Accounts.x_register_user(%{}, %{name: "Initial X Name", twin_origin: false})

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, updated_user} =
               Accounts.complete_x_user_profile(user, "x-user@example.com", "Updated X Name")

      assert updated_user.email == "x-user@example.com"
      assert updated_user.author.name == "Updated X Name"
    end)

    assert_enqueued(
      worker: NewUserSignupNotificationWorker,
      args: %{"name" => "Updated X Name", "email" => "x-user@example.com"}
    )
  end
end
