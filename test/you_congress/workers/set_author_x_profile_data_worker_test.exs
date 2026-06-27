defmodule YouCongress.Workers.SetAuthorXProfileDataWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import ExUnit.CaptureLog
  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures

  alias YouCongress.Authors
  alias YouCongress.Accounts.User
  alias YouCongress.Repo
  alias YouCongress.Workers.SetAuthorXProfileDataWorker
  alias YouCongress.X.XAPI

  describe "perform/1" do
    test "sets the author's X profile fields from the X API" do
      author = author_fixture(twitter_username: "some_username")
      image_url = "https://pbs.twimg.com/profile_images/123/abc_400x400.jpg"

      with_mock XAPI,
        fetch_user_by_username: fn "some_username" ->
          {:ok,
           %{
             twitter_id_str: "123456",
             profile_image_url: image_url,
             description: "X bio",
             followers_count: 42,
             friends_count: 24,
             verified: true,
             location: "Madrid",
             google_id: "google-123"
           }}
        end do
        assert :ok =
                 SetAuthorXProfileDataWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })

        author = Authors.get_author!(author.id)
        assert author.twitter_id_str == "123456"
        assert author.profile_image_url == image_url
        assert author.description == "X bio"
        assert author.followers_count == 42
        assert author.friends_count == 24
        assert author.verified == true
        assert author.location == "Madrid"
        assert author.google_id == "google-123"
      end
    end

    test "does not overwrite an existing profile_image_url when saving X metadata" do
      existing_image_url = "https://example.com/existing.jpg"

      author =
        author_fixture(
          twitter_username: "some_username",
          profile_image_url: existing_image_url
        )

      with_mock XAPI,
        fetch_user_by_username: fn "some_username" ->
          {:ok,
           %{
             profile_image_url: "https://pbs.twimg.com/profile_images/123/new_400x400.jpg",
             description: "Updated X bio"
           }}
        end do
        assert :ok =
                 SetAuthorXProfileDataWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })

        author = Authors.get_author!(author.id)
        assert author.profile_image_url == existing_image_url
        assert author.description == "Updated X bio"
      end
    end

    test "returns :ok when a duplicate X id is reassigned from an unlinked stale author" do
      old_author =
        author_fixture(
          twitter_username: "worker_stale_username",
          twitter_id_str: "worker-stable-x-id"
        )

      current_author =
        author_fixture(
          twitter_username: "worker_current_username",
          twitter_id_str: nil,
          profile_image_url: nil
        )

      with_mock XAPI,
        fetch_user_by_username: fn "worker_current_username" ->
          {:ok,
           %{
             twitter_id_str: "worker-stable-x-id",
             profile_image_url: "https://pbs.twimg.com/profile_images/123/worker_400x400.jpg",
             description: "Worker X bio"
           }}
        end do
        log =
          capture_warning_log(fn ->
            assert :ok =
                     SetAuthorXProfileDataWorker.perform(%Oban.Job{
                       args: %{"author_id" => current_author.id}
                     })
          end)

        assert log =~ "Reassigning duplicate X identity"

        old_author = Authors.get_author!(old_author.id)
        current_author = Authors.get_author!(current_author.id)

        assert old_author.twitter_id_str == nil
        assert old_author.twitter_username == nil
        assert current_author.twitter_id_str == "worker-stable-x-id"
        assert current_author.description == "Worker X bio"
      end
    end

    test "returns :ok when a duplicate X id transfer is skipped for a linked old author" do
      old_author =
        author_fixture(
          twitter_username: "worker_linked_old_username",
          twitter_id_str: "worker-linked-x-id"
        )

      user_for_author(old_author)

      current_author =
        author_fixture(
          twitter_username: "worker_linked_current_username",
          twitter_id_str: nil,
          profile_image_url: nil,
          description: nil
        )

      with_mock XAPI,
        fetch_user_by_username: fn "worker_linked_current_username" ->
          {:ok,
           %{
             twitter_id_str: "worker-linked-x-id",
             profile_image_url: "https://pbs.twimg.com/profile_images/123/linked_400x400.jpg",
             description: "Should not be saved"
           }}
        end do
        log =
          capture_warning_log(fn ->
            assert :ok =
                     SetAuthorXProfileDataWorker.perform(%Oban.Job{
                       args: %{"author_id" => current_author.id}
                     })
          end)

        assert log =~ "Skipped duplicate X identity reassignment"

        old_author = Authors.get_author!(old_author.id)
        current_author = Authors.get_author!(current_author.id)

        assert old_author.twitter_id_str == "worker-linked-x-id"
        assert old_author.twitter_username == "worker_linked_old_username"
        assert current_author.twitter_id_str == nil
        assert current_author.twitter_username == "worker_linked_current_username"
        assert current_author.profile_image_url == nil
        assert current_author.description == nil
      end
    end

    test "deletes the twitter_username without retrying when the X user is not found" do
      author = author_fixture(twitter_username: "missing_user")

      with_mock XAPI,
        fetch_user_by_username: fn "missing_user" -> {:error, "User not found"} end do
        assert :ok =
                 SetAuthorXProfileDataWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })

        author = Authors.get_author!(author.id)
        assert author.profile_image_url == nil
        assert author.twitter_username == nil
      end
    end

    test "returns :ok when the author has no twitter_username" do
      author = author_fixture(twitter_username: nil)

      assert :ok =
               SetAuthorXProfileDataWorker.perform(%Oban.Job{
                 args: %{"author_id" => author.id}
               })
    end

    test "returns :ok when the author does not exist" do
      assert :ok =
               SetAuthorXProfileDataWorker.perform(%Oban.Job{
                 args: %{"author_id" => -1}
               })
    end

    test "returns error on transient failures so Oban retries" do
      author = author_fixture(twitter_username: "some_username")

      with_mock XAPI,
        fetch_user_by_username: fn "some_username" -> {:error, "Request failed"} end do
        assert {:error, "Request failed"} =
                 SetAuthorXProfileDataWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })
      end
    end
  end

  defp user_for_author(author) do
    %User{}
    |> User.twitter_registration_changeset(%{
      "email" => unique_user_email(),
      "author_id" => author.id
    })
    |> Repo.insert!()
  end

  defp capture_warning_log(fun) do
    previous_level = Logger.level()
    Logger.configure(level: :warning)

    try do
      capture_log(fun)
    after
      Logger.configure(level: previous_level)
    end
  end
end
