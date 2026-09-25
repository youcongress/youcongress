defmodule YouCongress.AmplitudeTest do
  use YouCongress.DataCase, async: false
  use Oban.Testing, repo: YouCongress.Repo

  alias YouCongress.Amplitude
  alias YouCongress.Workers.AmplitudeEventWorker

  setup do
    previous_key = Application.get_env(:you_congress, :amplitude_api_key)
    Application.put_env(:you_congress, :amplitude_api_key, "test-key")

    on_exit(fn -> Application.put_env(:you_congress, :amplitude_api_key, previous_key) end)
  end

  test "does not queue an event without explicit consent" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = Amplitude.track_event("Test event", "user-123")
      refute_enqueued(worker: AmplitudeEventWorker)
    end)
  end

  test "queues consented events with the consent marker" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %Oban.Job{}} =
               Amplitude.track_event("Test event", "user-123", %{}, analytics_consent: true)

      assert_enqueued(
        worker: AmplitudeEventWorker,
        args: %{
          "event_type" => "Test event",
          "user_id" => "user-123",
          "analytics_consent" => true
        }
      )
    end)
  end

  test "does not deliver an event without explicit consent" do
    assert :ok = Amplitude.deliver_event("Test event", "user-123")
  end
end
