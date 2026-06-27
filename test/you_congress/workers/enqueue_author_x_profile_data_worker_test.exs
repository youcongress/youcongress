defmodule YouCongress.Workers.EnqueueAuthorXProfileDataWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AuthorsFixtures

  alias YouCongress.Workers.EnqueueAuthorXProfileDataWorker
  alias YouCongress.Workers.SetAuthorXProfileDataWorker

  describe "perform/1" do
    test "enqueues a job for each author with an X username and incomplete X profile data" do
      author1 = author_fixture(twitter_username: "user_one")

      author2 =
        author_fixture(
          twitter_username: "user_two",
          profile_image_url: "https://pbs.twimg.com/profile_images/123/abc_400x400.jpg",
          twitter_id_str: "123",
          followers_count: nil,
          friends_count: 10,
          verified: false
        )

      complete =
        author_fixture(
          twitter_username: "user_three",
          profile_image_url: "https://pbs.twimg.com/profile_images/123/abc_400x400.jpg",
          twitter_id_str: "456",
          followers_count: 100,
          friends_count: 50,
          verified: false
        )

      without_username = author_fixture(twitter_username: nil)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueAuthorXProfileDataWorker.perform(%Oban.Job{args: %{}})
      end)

      assert_enqueued(
        worker: SetAuthorXProfileDataWorker,
        args: %{author_id: author1.id}
      )

      assert_enqueued(
        worker: SetAuthorXProfileDataWorker,
        args: %{author_id: author2.id}
      )

      refute_enqueued(
        worker: SetAuthorXProfileDataWorker,
        args: %{author_id: complete.id}
      )

      refute_enqueued(
        worker: SetAuthorXProfileDataWorker,
        args: %{author_id: without_username.id}
      )
    end

    test "enqueues nothing when all authors have complete X profile data" do
      author_fixture(
        twitter_username: "user_one",
        profile_image_url: "https://pbs.twimg.com/profile_images/123/abc_400x400.jpg",
        twitter_id_str: "123",
        followers_count: 100,
        friends_count: 50,
        verified: false
      )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueAuthorXProfileDataWorker.perform(%Oban.Job{args: %{}})
      end)

      refute_enqueued(worker: SetAuthorXProfileDataWorker)
    end
  end
end
