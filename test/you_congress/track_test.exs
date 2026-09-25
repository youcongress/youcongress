defmodule YouCongress.TrackTest do
  use YouCongress.DataCase, async: true
  use Oban.Testing, repo: YouCongress.Repo

  alias YouCongress.{AnalyticsConsent, Track}
  alias YouCongress.Accounts.User
  alias YouCongress.Workers.TrackWorker

  setup do
    AnalyticsConsent.set_for_process(false)
    :ok
  end

  test "does not enqueue an event without analytics consent" do
    user = %User{id: 123, author_id: nil}

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = Track.event("Test event", user)
      refute_enqueued(worker: TrackWorker)
    end)
  end

  test "records consent when enqueueing an event" do
    user = %User{id: 123, author_id: nil}
    AnalyticsConsent.set_for_process(true)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %Oban.Job{}} = Track.event("Test event", user)

      assert_enqueued(
        worker: TrackWorker,
        args: %{
          "event_type" => "Test event",
          "current_user_id" => 123,
          "analytics_consent" => true
        }
      )
    end)
  end
end
