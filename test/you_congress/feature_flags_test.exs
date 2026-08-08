defmodule YouCongress.FeatureFlagsTest do
  use ExUnit.Case, async: true

  alias YouCongress.FeatureFlags

  test "parses supported flags from FEATURE_FLAGS" do
    assert FeatureFlags.overrides_from_env("automatic_verifications=false,ai_policy_launch=true") ==
             %{
               automatic_verifications: false,
               ai_policy_launch: true
             }
  end
end
