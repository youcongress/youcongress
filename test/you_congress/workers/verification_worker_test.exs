defmodule YouCongress.Workers.VerificationWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures

  alias YouCongress.Opinions
  alias YouCongress.Workers.VerificationPollingWorker
  alias YouCongress.Workers.VerificationWorker

  defmodule FailingVerifier do
    @behaviour YouCongress.Verifications.Verifier

    def submit(_subject_type, _record), do: {:error, :submission_failed}
    def check_job_status(_job_id), do: {:error, :polling_failed}
  end

  defp put_env_restore(key, value) do
    original = Application.fetch_env(:you_congress, key)
    Application.put_env(:you_congress, key, value)

    on_exit(fn ->
      case original do
        {:ok, original_value} -> Application.put_env(:you_congress, key, original_value)
        :error -> Application.delete_env(:you_congress, key)
      end
    end)
  end

  defp insert_job(worker, args) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      args
      |> worker.new()
      |> Oban.insert()
    end)
  end

  defp run_worker(worker, job) do
    Oban.Testing.with_testing_mode(:manual, fn -> worker.perform(job) end)
  end

  test "stores submission and polling job details in metadata" do
    opinion = opinion_fixture()
    opinion_id = opinion.id
    verification_job_id = "fake:quote:#{opinion.id}"
    {:ok, job} = insert_job(VerificationWorker, %{"subject" => "quote", "id" => opinion.id})

    assert :ok = run_worker(VerificationWorker, job)

    assert %{
             "status" => "submitted",
             "subject" => "quote",
             "subject_id" => ^opinion_id,
             "verification_job_id" => ^verification_job_id
           } = YouCongress.Repo.reload!(job).meta["verification"]

    assert [polling_job] = all_enqueued(worker: VerificationPollingWorker)

    assert %Oban.Job{args: %{"verification_worker_job_id" => parent_job_id}} =
             polling_job

    assert parent_job_id == job.id
  end

  test "stores why an ineligible verification was skipped" do
    {:ok, job} = insert_job(VerificationWorker, %{"subject" => "quote", "id" => -1})

    assert :ok = run_worker(VerificationWorker, job)

    assert %{
             "status" => "skipped",
             "subject" => "quote",
             "subject_id" => -1,
             "reason" => "quote_not_found"
           } = YouCongress.Repo.reload!(job).meta["verification"]
  end

  test "stores the completed verifier result in polling job metadata" do
    opinion = opinion_fixture()
    opinion_id = opinion.id
    verification_job_id = "fake:quote:#{opinion.id}"
    user = user_fixture()
    put_env_restore(:verification_user_id, user.id)

    {:ok, verification_job} =
      insert_job(VerificationWorker, %{"subject" => "quote", "id" => opinion.id})

    {:ok, job} =
      insert_job(VerificationPollingWorker, %{
        "subject" => "quote",
        "id" => opinion.id,
        "job_id" => "fake:quote:#{opinion.id}",
        "verification_worker_job_id" => verification_job.id
      })

    assert :ok = run_worker(VerificationPollingWorker, job)

    assert %{
             "status" => "completed",
             "outcome" => "ai_verified",
             "subject" => "quote",
             "subject_id" => ^opinion_id,
             "verification_job_id" => ^verification_job_id,
             "result" => %{
               "status" => "ai_verified",
               "comment" => "Fake verification",
               "model" => "fake-llm"
             }
           } = YouCongress.Repo.reload!(job).meta["verification"]

    assert %{
             "status" => "completed",
             "outcome" => "ai_verified",
             "polling_job_id" => polling_job_id
           } = YouCongress.Repo.reload!(verification_job).meta["verification"]

    assert polling_job_id == job.id

    assert Opinions.get_opinion!(opinion.id).verification_status == :ai_verified
  end

  test "stores submission and polling failures in metadata" do
    opinion = opinion_fixture()
    put_env_restore(:quote_verifier_implementation, FailingVerifier)

    {:ok, submission_job} =
      insert_job(VerificationWorker, %{"subject" => "quote", "id" => opinion.id})

    assert {:error, :submission_failed} = run_worker(VerificationWorker, submission_job)

    assert %{
             "status" => "failed",
             "stage" => "submit",
             "reason" => "submission_failed"
           } = YouCongress.Repo.reload!(submission_job).meta["verification"]

    {:ok, polling_job} =
      insert_job(VerificationPollingWorker, %{
        "subject" => "quote",
        "id" => opinion.id,
        "job_id" => "failed-job"
      })

    assert {:cancel, :polling_failed} = run_worker(VerificationPollingWorker, polling_job)

    assert %{
             "status" => "cancelled",
             "reason" => "polling_failed"
           } = YouCongress.Repo.reload!(polling_job).meta["verification"]
  end
end
