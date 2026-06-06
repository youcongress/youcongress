defmodule YouCongress.Workers.EnqueueAuthorProfileImagesFromXWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AuthorsFixtures

  alias YouCongress.Workers.EnqueueAuthorProfileImagesFromXWorker
  alias YouCongress.Workers.SetAuthorProfileImageFromXWorker

  describe "perform/1" do
    test "enqueues a job for each author with an X username and no profile image" do
      author1 = author_fixture(twitter_username: "user_one")
      author2 = author_fixture(twitter_username: "user_two")

      with_image =
        author_fixture(
          twitter_username: "user_three",
          profile_image_url: "https://pbs.twimg.com/profile_images/123/abc_400x400.jpg"
        )

      without_username = author_fixture(twitter_username: nil)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueAuthorProfileImagesFromXWorker.perform(%Oban.Job{args: %{}})
      end)

      assert_enqueued(
        worker: SetAuthorProfileImageFromXWorker,
        args: %{author_id: author1.id}
      )

      assert_enqueued(
        worker: SetAuthorProfileImageFromXWorker,
        args: %{author_id: author2.id}
      )

      refute_enqueued(
        worker: SetAuthorProfileImageFromXWorker,
        args: %{author_id: with_image.id}
      )

      refute_enqueued(
        worker: SetAuthorProfileImageFromXWorker,
        args: %{author_id: without_username.id}
      )
    end

    test "enqueues nothing when all authors have profile images" do
      author_fixture(
        twitter_username: "user_one",
        profile_image_url: "https://pbs.twimg.com/profile_images/123/abc_400x400.jpg"
      )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueAuthorProfileImagesFromXWorker.perform(%Oban.Job{args: %{}})
      end)

      refute_enqueued(worker: SetAuthorProfileImageFromXWorker)
    end
  end
end
