defmodule YouCongress.AnalyticsConsent do
  @moduledoc """
  Stores analytics consent for the lifetime of the current request or LiveView process.

  Consent defaults to false so background jobs and non-browser callers cannot
  accidentally enable analytics.
  """

  @process_key {__MODULE__, :granted}

  @spec set_for_process(boolean()) :: boolean()
  def set_for_process(granted?) when is_boolean(granted?) do
    Process.put(@process_key, granted?)
    granted?
  end

  @spec granted?() :: boolean()
  def granted?, do: Process.get(@process_key, false) == true
end
