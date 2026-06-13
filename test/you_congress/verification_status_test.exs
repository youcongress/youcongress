defmodule YouCongress.VerificationStatusTest do
  use ExUnit.Case, async: true

  alias YouCongress.VerificationStatus, as: VS

  describe "positive?/1" do
    test "endorsed, verified and ai_verified are positive" do
      assert VS.positive?(:endorsed)
      assert VS.positive?(:verified)
      assert VS.positive?(:ai_verified)
    end

    test "everything else is not positive" do
      refute VS.positive?(nil)
      refute VS.positive?(:unverified)
      refute VS.positive?(:disputed)
      refute VS.positive?(:unverifiable)
      refute VS.positive?(:ai_unverifiable)
    end
  end

  describe "aggregate/3" do
    test "all unset is unverified" do
      assert VS.aggregate(nil, nil, nil) == :unverified
    end

    test "stalls at the first unset pipeline step" do
      assert VS.aggregate(:verified, nil, nil) == :unverified
      assert VS.aggregate(:verified, :verified, nil) == :unverified
    end

    test "all positive and all human is verified" do
      assert VS.aggregate(:verified, :verified, :verified) == :verified
    end

    test "endorsed counts as human-positive" do
      assert VS.aggregate(:endorsed, :verified, :verified) == :verified
    end

    test "any ai_verified step downgrades the aggregate to ai_verified" do
      assert VS.aggregate(:ai_verified, :verified, :verified) == :ai_verified
      assert VS.aggregate(:verified, :ai_verified, :verified) == :ai_verified
      assert VS.aggregate(:verified, :verified, :ai_verified) == :ai_verified
    end

    test "disputed anywhere dominates, even out of pipeline order" do
      assert VS.aggregate(:verified, :disputed, :verified) == :disputed
      assert VS.aggregate(nil, nil, :disputed) == :disputed
      assert VS.aggregate(:disputed, nil, nil) == :disputed
    end

    test "unverifiable on the reached step surfaces as unverifiable" do
      assert VS.aggregate(:unverifiable, nil, nil) == :unverifiable
      assert VS.aggregate(:ai_unverifiable, nil, nil) == :unverifiable
      assert VS.aggregate(:verified, :unverifiable, nil) == :unverifiable
    end

    test "accepts string statuses" do
      assert VS.aggregate("verified", "verified", "verified") == :verified
      assert VS.aggregate("disputed", nil, nil) == :disputed
    end
  end
end
