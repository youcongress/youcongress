defmodule YouCongress.FeatureFlagsTest do
  use ExUnit.Case, async: true

  alias YouCongress.FeatureFlags

  test "parses automatic_verifications from FEATURE_FLAGS" do
    assert FeatureFlags.overrides_from_env("automatic_verifications=false") == %{
             automatic_verifications: false
           }
  end
end
