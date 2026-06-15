defmodule YouCongress.Workers.FreshQuoteDiscoveryWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures

  alias YouCongress.Workers.FreshQuoteDiscoveryPollingWorker
  alias YouCongress.Workers.FreshQuoteDiscoveryWorker

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

  defp delete_env_restore(key) do
    original = Application.fetch_env(:you_congress, key)
    Application.delete_env(:you_congress, key)

    on_exit(fn ->
      case original do
        {:ok, original_value} -> Application.put_env(:you_congress, key, original_value)
        :error -> Application.delete_env(:you_congress, key)
      end
    end)
  end

  describe "perform/1" do
    test "starts discovery with recent quote inventory and enqueues polling" do
      user = user_fixture()
      existing_quote = opinion_fixture(%{content: "Existing AI safety quote", twin: false})
      put_env_restore(:verification_user_id, user.id)
      put_env_restore(:fresh_quote_finder_test_pid, self())
      put_env_restore(:fresh_quote_finder_test_job_id, "fresh-job-1")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = FreshQuoteDiscoveryWorker.perform(%Oban.Job{args: %{}})
      end)

      assert_received {:fresh_quote_find_quote, inventory, opts}
      assert [%{id: quote_id, quote: "Existing AI safety quote"}] = inventory
      assert quote_id == existing_quote.id
      assert Keyword.fetch!(opts, :limit) == 1

      assert_enqueued(
        worker: FreshQuoteDiscoveryPollingWorker,
        args: %{"job_id" => "fresh-job-1", "user_id" => user.id, "limit" => 1}
      )
    end

    test "skips when verification_user_id is not configured" do
      delete_env_restore(:verification_user_id)
      put_env_restore(:fresh_quote_finder_test_pid, self())

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = FreshQuoteDiscoveryWorker.perform(%Oban.Job{args: %{}})
      end)

      refute_received {:fresh_quote_find_quote, _inventory, _opts}
      refute_enqueued(worker: FreshQuoteDiscoveryPollingWorker)
    end
  end
end
