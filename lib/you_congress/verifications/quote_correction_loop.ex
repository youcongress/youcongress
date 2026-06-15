defmodule YouCongress.Verifications.QuoteCorrectionLoop do
  @moduledoc false

  @max_correction_attempts 2

  def correction_attempts(args_or_opts), do: normalize(fetch_attempts(args_or_opts))

  def next_attempt(args_or_opts), do: correction_attempts(args_or_opts) + 1

  def allow_correction?(args_or_opts),
    do: correction_attempts(args_or_opts) < @max_correction_attempts

  def maybe_put_attempt(args, nil), do: args
  def maybe_put_attempt(args, attempt), do: Map.put(args, "correction_attempts", attempt)

  defp fetch_attempts(%{} = args) do
    Map.get(args, "correction_attempts") || Map.get(args, :correction_attempts)
  end

  defp fetch_attempts(opts) when is_list(opts), do: Keyword.get(opts, :correction_attempts)
  defp fetch_attempts(_), do: nil

  defp normalize(nil), do: 0
  defp normalize(attempts) when is_integer(attempts) and attempts >= 0, do: attempts

  defp normalize(attempts) when is_binary(attempts) do
    case Integer.parse(attempts) do
      {attempts, ""} when attempts >= 0 -> attempts
      _ -> 0
    end
  end

  defp normalize(_), do: 0
end
