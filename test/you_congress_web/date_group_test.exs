defmodule YouCongressWeb.DateGroupTest do
  use ExUnit.Case, async: true

  alias YouCongressWeb.DateGroup

  # A Saturday. Its week (Monday-based) starts on 2026-08-24.
  @today ~D[2026-08-29]

  defp label(date, precision \\ :day) do
    {date, precision} |> DateGroup.bucket(@today) |> DateGroup.label()
  end

  describe "bucket/2 and label/1 with day precision" do
    test "labels the current and previous day" do
      assert label(~D[2026-08-29]) == "Today"
      assert label(~D[2026-08-28]) == "Yesterday"
    end

    test "labels a future date as today" do
      assert label(~D[2026-09-05]) == "Today"
    end

    test "labels the rest of the current week" do
      assert label(~D[2026-08-27]) == "Earlier this week"
      assert label(~D[2026-08-24]) == "Earlier this week"
    end

    test "labels the previous week" do
      assert label(~D[2026-08-23]) == "Last week"
      assert label(~D[2026-08-17]) == "Last week"
    end

    test "labels the rest of the current month" do
      assert label(~D[2026-08-16]) == "Earlier this month"
      assert label(~D[2026-08-01]) == "Earlier this month"
    end

    test "labels the previous month" do
      assert label(~D[2026-07-31]) == "Last month"
      assert label(~D[2026-07-01]) == "Last month"
    end

    test "labels older months of the current year by name" do
      assert label(~D[2026-06-30]) == "June 2026"
      assert label(~D[2026-01-05]) == "January 2026"
    end

    test "labels previous years by year" do
      assert label(~D[2025-12-31]) == "2025"
      assert label(~D[1963-08-28]) == "1963"
    end
  end

  describe "bucket/2 with coarser precisions" do
    test "a month-precision date never lands in a day or week bucket" do
      assert label(~D[2026-08-01], :month) == "Earlier this month"
      assert label(~D[2026-07-01], :month) == "Last month"
      assert label(~D[2026-06-01], :month) == "June 2026"
      assert label(~D[2024-06-01], :month) == "2024"
    end

    test "a year-precision date only lands in a year bucket" do
      assert label(~D[2026-01-01], :year) == "2026"
      assert label(~D[2026-08-29], :year) == "2026"
      assert label(~D[1863-01-01], :year) == "1863"
    end
  end

  describe "bucket/2 without a date" do
    test "labels undated items" do
      assert DateGroup.bucket(nil, @today) |> DateGroup.label() == "Undated"
      assert DateGroup.bucket({nil, :day}, @today) |> DateGroup.label() == "Undated"
    end
  end

  describe "group/3" do
    test "chunks consecutive items sharing a bucket, keeping their order" do
      items = [
        {:a, ~D[2026-08-29]},
        {:b, ~D[2026-08-29]},
        {:c, ~D[2026-08-28]},
        {:d, ~D[2026-08-25]},
        {:e, ~D[2019-04-02]}
      ]

      groups = DateGroup.group(items, fn {_, date} -> {date, :day} end, @today)

      assert Enum.map(groups, & &1.label) == [
               "Today",
               "Yesterday",
               "Earlier this week",
               "2019"
             ]

      assert Enum.map(groups, & &1.count) == [2, 1, 1, 1]
      assert groups |> Enum.flat_map(& &1.items) |> Enum.map(&elem(&1, 0)) == [:a, :b, :c, :d, :e]
    end

    test "returns no groups for an empty list" do
      assert DateGroup.group([], fn _ -> nil end, @today) == []
    end
  end
end
