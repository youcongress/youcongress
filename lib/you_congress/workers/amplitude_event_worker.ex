defmodule YouCongress.Workers.AmplitudeEventWorker do
  @moduledoc """
  Worker responsible for delivering queued events to Amplitude.
  """

  use Oban.Worker, queue: :amplitude

  alias YouCongress.Amplitude

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_type" => event_type} = args}) do
    user_id = Map.get(args, "user_id")
    properties = Map.get(args, "event_properties") || %{}
    device_id = Map.get(args, "device_id")

    Amplitude.deliver_event(event_type, user_id, properties, device_id: device_id)
  end
end
