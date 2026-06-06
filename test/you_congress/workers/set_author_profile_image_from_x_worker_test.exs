defmodule YouCongress.Workers.SetAuthorProfileImageFromXWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import Mock
  import YouCongress.AuthorsFixtures

  alias YouCongress.Authors
  alias YouCongress.Workers.SetAuthorProfileImageFromXWorker
  alias YouCongress.X.XAPI

  describe "perform/1" do
    test "sets the author's profile_image_url from the X API" do
      author = author_fixture(twitter_username: "some_username")
      image_url = "https://pbs.twimg.com/profile_images/123/abc_400x400.jpg"

      with_mock XAPI,
        fetch_user_by_username: fn "some_username" ->
          {:ok, %{profile_image_url: image_url}}
        end do
        assert :ok =
                 SetAuthorProfileImageFromXWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })

        assert Authors.get_author!(author.id).profile_image_url == image_url
      end
    end

    test "returns :ok without retrying when the X user is not found" do
      author = author_fixture(twitter_username: "missing_user")

      with_mock XAPI,
        fetch_user_by_username: fn "missing_user" -> {:error, "User not found"} end do
        assert :ok =
                 SetAuthorProfileImageFromXWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })

        assert Authors.get_author!(author.id).profile_image_url == nil
      end
    end

    test "returns :ok when the author has no twitter_username" do
      author = author_fixture(twitter_username: nil)

      assert :ok =
               SetAuthorProfileImageFromXWorker.perform(%Oban.Job{
                 args: %{"author_id" => author.id}
               })
    end

    test "returns :ok when the author does not exist" do
      assert :ok =
               SetAuthorProfileImageFromXWorker.perform(%Oban.Job{
                 args: %{"author_id" => -1}
               })
    end

    test "returns error on transient failures so Oban retries" do
      author = author_fixture(twitter_username: "some_username")

      with_mock XAPI,
        fetch_user_by_username: fn "some_username" -> {:error, "Request failed"} end do
        assert {:error, "Request failed"} =
                 SetAuthorProfileImageFromXWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })
      end
    end
  end
end
