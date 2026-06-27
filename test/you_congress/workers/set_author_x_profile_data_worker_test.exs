defmodule YouCongress.Workers.SetAuthorXProfileDataWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import Mock
  import YouCongress.AuthorsFixtures

  alias YouCongress.Authors
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
end
