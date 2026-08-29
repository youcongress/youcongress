defmodule YouCongressWeb.DateGroup do
  @moduledoc """
  Groups feed items into human date buckets so a feed reads as a timeline
  instead of a flat list.

  The ladder walks from fine to coarse: `Today`, `Yesterday`,
  `Earlier this week`, `Last week`, `Earlier this month`, `Last month`,
  then a month name for older dates in the current year (`June 2026`) and
  finally a plain year (`2024`). Items without a date fall into `Undated`.

  Buckets are calendar-based in UTC and weeks start on Monday.

  Opinion dates carry a precision (`:day`, `:month`, `:year`), so a bucket is
  never finer than what is actually known: a month-precision date starts the
  ladder at `Earlier this month`, and a year-precision date only ever lands in
  a year bucket.
  """

  @type item_date :: {Date.t() | nil, atom | nil} | Date.t() | nil
  @type group :: %{key: term, label: String.t(), count: non_neg_integer, items: list}

  @doc """
  Splits `items` into consecutive date groups.

  `date_fun` returns `{date, precision}` (or a `Date`, or `nil`) for an item.
  Items are expected to be sorted by date already: only consecutive runs are
  grouped, so the feed order is never rearranged.
  """
  @spec group(list, (term -> item_date), Date.t()) :: [group]
  def group(items, date_fun, today \\ Date.utc_today()) do
    items
    |> Enum.chunk_by(fn item -> item |> date_fun.() |> bucket(today) end)
    |> Enum.map(fn [first | _] = chunk ->
      key = first |> date_fun.() |> bucket(today)

      %{key: key, label: label(key), count: length(chunk), items: chunk}
    end)
  end

  @doc """
  Returns the bucket key for an item date, relative to `today`.
  """
  @spec bucket(item_date, Date.t()) :: term
  def bucket(nil, _today), do: :undated
  def bucket({nil, _precision}, _today), do: :undated
  def bucket(%Date{} = date, today), do: bucket({date, :day}, today)
  def bucket({%Date{} = date, :year}, _today), do: {:year, date.year}
  def bucket({%Date{} = date, :month}, today), do: month_bucket(date, today)
  def bucket({%Date{} = date, _precision}, today), do: day_bucket(date, today)

  @doc """
  Returns the human label for a bucket key.
  """
  @spec label(term) :: String.t()
  def label(:today), do: "Today"
  def label(:yesterday), do: "Yesterday"
  def label(:this_week), do: "Earlier this week"
  def label(:last_week), do: "Last week"
  def label(:this_month), do: "Earlier this month"
  def label(:last_month), do: "Last month"
  def label(:undated), do: "Undated"
  def label({:year, year}), do: pad_year(year)

  def label({:month, year, month}) do
    "#{Calendar.strftime(%Date{year: 2000, month: month, day: 1}, "%B")} #{pad_year(year)}"
  end

  defp day_bucket(date, today) do
    week_start = Date.beginning_of_week(today, :monday)

    cond do
      not before?(date, today) -> :today
      date == Date.add(today, -1) -> :yesterday
      not before?(date, week_start) -> :this_week
      not before?(date, Date.add(week_start, -7)) -> :last_week
      true -> month_bucket(date, today)
    end
  end

  defp month_bucket(date, today) do
    last_month = Date.add(Date.beginning_of_month(today), -1)

    cond do
      same_month?(date, today) -> :this_month
      same_month?(date, last_month) -> :last_month
      date.year == today.year -> {:month, date.year, date.month}
      true -> {:year, date.year}
    end
  end

  defp same_month?(a, b), do: a.year == b.year and a.month == b.month

  defp before?(a, b), do: Date.compare(a, b) == :lt

  defp pad_year(year) when year < 1000, do: String.pad_leading("#{year}", 4, "0")
  defp pad_year(year), do: "#{year}"
end
