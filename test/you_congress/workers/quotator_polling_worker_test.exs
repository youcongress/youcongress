defmodule YouCongress.Workers.QuotatorPollingWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import Mock
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Workers.QuotatorPollingWorker
  alias YouCongress.Opinions.Quotes.{Quotator, QuotatorAI}

  describe "perform/1" do
    test "enqueues QuotatorWorker with correct max_remaining_quotes when job completes" do
      statement = statement_fixture()
      user = user_fixture()
      job_id = "job_123"
      initial_max_quotes = 10
      saved_quotes_count = 5

      with_mock QuotatorAI,
        check_job_status: fn ^job_id -> {:ok, :completed, %{quotes: [%{}]}} end do
        with_mock Quotator,
          save_quotes_from_job: fn _args -> {:ok, saved_quotes_count} end,
          find_and_save_quotes: fn _v, _e, _u, _c, _q, _t -> {:ok, :job_started} end do
          QuotatorPollingWorker.perform(%Oban.Job{
            args: %{
              "job_id" => job_id,
              "statement_id" => statement.id,
              "user_id" => user.id,
              "max_remaining_llm_calls" => 3,
              "max_remaining_quotes" => initial_max_quotes,
              "total_quotes_added" => 0
            }
          })

          assert_called(
            Quotator.find_and_save_quotes(
              statement.id,
              :_,
              user.id,
              2,
              initial_max_quotes - saved_quotes_count,
              saved_quotes_count
            )
          )
        end
      end
    end
  end
end
