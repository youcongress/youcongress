defmodule YouCongressWeb.Tools.TimeAgo do
  @moduledoc """
  Provides utility functions for formatting time differences in a human-readable format.
  """

  def short_time(datetime)
      when is_struct(datetime, DateTime) or is_struct(datetime, NaiveDateTime) do
    datetime =
      case datetime do
        %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
        %DateTime{} -> datetime
      end

    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}min ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 2_592_000 -> "#{div(diff, 86_400)}d ago"
      diff < 31_536_000 -> "#{div(diff, 2_592_000)}mo ago"
      true -> "#{div(diff, 31_536_000)}y ago"
    end
  end

  def short_time(_), do: ""
end
