defmodule YouCongress.Workers.SetAuthorCountryFromLLMWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AuthorsFixtures
  import YouCongress.CountriesFixtures

  alias YouCongress.Authors
  alias YouCongress.Workers.SetAuthorCountryFromLLMWorker

  defmodule SpainInference do
    def infer_country(_author, _model),
      do: {:ok, %{should_update: true, country: "Spain", reason: "Location is Madrid"}}
  end

  defmodule UnknownInference do
    def infer_country(_author, _model),
      do: {:ok, %{should_update: false, country: nil, reason: "Ambiguous"}}
  end

  defmodule InvalidCountryInference do
    def infer_country(_author, _model),
      do: {:ok, %{should_update: true, country: "Atlantis", reason: "Invalid"}}
  end

  defmodule ErrorInference do
    def infer_country(_author, _model), do: {:error, "timeout"}
  end

  setup do
    original = Application.get_env(:you_congress, :author_country_inference_implementation)

    on_exit(fn ->
      Application.put_env(:you_congress, :author_country_inference_implementation, original)
    end)
  end

  describe "perform/1" do
    test "updates an author country when inference returns a known country" do
      country = country_fixture(name: "Spain", iso_alpha2: "ES")

      author =
        author_fixture(
          name: "Pedro Sanchez",
          bio: "Prime Minister",
          location: "Madrid",
          country_id: nil,
          twitter_username: nil
        )

      Application.put_env(
        :you_congress,
        :author_country_inference_implementation,
        SpainInference
      )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 SetAuthorCountryFromLLMWorker.perform(%Oban.Job{
                   args: %{"author_id" => author.id}
                 })
      end)

      assert Authors.get_author!(author.id).country_id == country.id
    end

    test "does not update when inference is unsure" do
      author = author_fixture(country_id: nil, twitter_username: nil)

      Application.put_env(
        :you_congress,
        :author_country_inference_implementation,
        UnknownInference
      )

      assert :ok =
               SetAuthorCountryFromLLMWorker.perform(%Oban.Job{
                 args: %{"author_id" => author.id}
               })

      assert is_nil(Authors.get_author!(author.id).country_id)
    end

    test "does not update when inferred country is not in the countries table" do
      author = author_fixture(country_id: nil, twitter_username: nil)

      Application.put_env(
        :you_congress,
        :author_country_inference_implementation,
        InvalidCountryInference
      )

      assert :ok =
               SetAuthorCountryFromLLMWorker.perform(%Oban.Job{
                 args: %{"author_id" => author.id}
               })

      assert is_nil(Authors.get_author!(author.id).country_id)
    end

    test "does not overwrite an author with an existing country" do
      spain = country_fixture(name: "Spain", iso_alpha2: "ES")
      france = country_fixture(name: "France", iso_alpha2: "FR")
      author = author_fixture(country_id: france.id, twitter_username: nil)

      Application.put_env(
        :you_congress,
        :author_country_inference_implementation,
        SpainInference
      )

      assert :ok =
               SetAuthorCountryFromLLMWorker.perform(%Oban.Job{
                 args: %{"author_id" => author.id}
               })

      assert Authors.get_author!(author.id).country_id == france.id
      refute Authors.get_author!(author.id).country_id == spain.id
    end

    test "returns an error when inference fails so Oban retries" do
      author = author_fixture(country_id: nil, twitter_username: nil)

      Application.put_env(
        :you_congress,
        :author_country_inference_implementation,
        ErrorInference
      )

      assert {:error, "timeout"} =
               SetAuthorCountryFromLLMWorker.perform(%Oban.Job{
                 args: %{"author_id" => author.id}
               })
    end
  end
end
