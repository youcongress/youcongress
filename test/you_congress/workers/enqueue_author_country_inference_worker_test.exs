defmodule YouCongress.Workers.EnqueueAuthorCountryInferenceWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AuthorsFixtures
  import YouCongress.CountriesFixtures

  alias YouCongress.Workers.EnqueueAuthorCountryInferenceWorker
  alias YouCongress.Workers.SetAuthorCountryFromLLMWorker

  describe "perform/1" do
    test "enqueues a job for each author without a country" do
      author1 = author_fixture(country_id: nil, twitter_username: nil)
      author2 = author_fixture(country_id: nil, twitter_username: nil)
      country = country_fixture(name: "Spain", iso_alpha2: "ES")
      with_country = author_fixture(country_id: country.id, twitter_username: nil)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueAuthorCountryInferenceWorker.perform(%Oban.Job{args: %{}})
      end)

      assert_enqueued(
        worker: SetAuthorCountryFromLLMWorker,
        args: %{author_id: author1.id}
      )

      assert_enqueued(
        worker: SetAuthorCountryFromLLMWorker,
        args: %{author_id: author2.id}
      )

      refute_enqueued(
        worker: SetAuthorCountryFromLLMWorker,
        args: %{author_id: with_country.id}
      )
    end

    test "enqueues nothing when all authors have countries" do
      country = country_fixture(name: "Spain", iso_alpha2: "ES")
      author_fixture(country_id: country.id, twitter_username: nil)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueAuthorCountryInferenceWorker.perform(%Oban.Job{args: %{}})
      end)

      refute_enqueued(worker: SetAuthorCountryFromLLMWorker)
    end
  end
end
