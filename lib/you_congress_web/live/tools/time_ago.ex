defmodule YouCongressWeb.Tools.TimeAgo do
  def short_time(datetime) when is_struct(datetime, DateTime) or is_struct(datetime, NaiveDateTime) do
    datetime = case datetime do
      %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
      %DateTime{} -> datetime
    end

    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}min ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 2592000 -> "#{div(diff, 86400)}d ago"
      diff < 31536000 -> "#{div(diff, 2592000)}mo ago"
      true -> "#{div(diff, 31536000)}y ago"
    end
  end

  def short_time(_), do: ""
end
