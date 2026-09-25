defmodule YouCongress.AnalyticsConsentTest do
  use ExUnit.Case, async: true

  alias YouCongress.AnalyticsConsent

  setup do
    AnalyticsConsent.set_for_process(false)
    :ok
  end

  test "consent is denied by default" do
    refute Task.async(fn -> AnalyticsConsent.granted?() end) |> Task.await()
    refute AnalyticsConsent.granted?()
  end

  test "consent can be enabled and disabled for the current process" do
    assert AnalyticsConsent.set_for_process(true)
    assert AnalyticsConsent.granted?()

    refute AnalyticsConsent.set_for_process(false)
    refute AnalyticsConsent.granted?()
  end
end
