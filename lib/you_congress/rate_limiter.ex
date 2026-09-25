defmodule YouCongress.RateLimiter do
  @moduledoc """
  A database-backed fixed-window limiter shared by every application node.

  Identifiers are SHA-256 hashed before storage so email addresses, phone
  numbers, API keys, and IP addresses are not retained in the limiter table.
  """

  alias YouCongress.RateLimiter.RateLimit
  alias YouCongress.Repo

  @spec check(atom() | String.t(), term(), pos_integer(), pos_integer()) ::
          :ok | {:error, {:rate_limited, pos_integer()}}
  def check(scope, key, limit, window_seconds)
      when is_integer(limit) and limit > 0 and is_integer(window_seconds) and window_seconds > 0 do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    timestamp = DateTime.to_naive(now)
    bucket_unix = div(DateTime.to_unix(now), window_seconds) * window_seconds
    bucket_start = DateTime.from_unix!(bucket_unix)

    entry = %{
      scope: to_string(scope),
      key_hash: hash_key(key),
      bucket_start: bucket_start,
      count: 1,
      inserted_at: timestamp,
      updated_at: timestamp
    }

    {_count, [%{count: current_count}]} =
      Repo.insert_all(RateLimit, [entry],
        on_conflict: [inc: [count: 1], set: [updated_at: timestamp]],
        conflict_target: [:scope, :key_hash, :bucket_start],
        returning: [:count]
      )

    if current_count <= limit do
      :ok
    else
      retry_after = bucket_unix + window_seconds - DateTime.to_unix(now)

      :telemetry.execute(
        [:you_congress, :rate_limiter, :blocked],
        %{count: 1},
        %{scope: to_string(scope), retry_after: max(retry_after, 1)}
      )

      {:error, {:rate_limited, max(retry_after, 1)}}
    end
  end

  @spec allowed?(atom() | String.t(), term(), pos_integer(), pos_integer()) :: boolean()
  def allowed?(scope, key, limit, window_seconds) do
    check(scope, key, limit, window_seconds) == :ok
  end

  @spec normalize_identity(term()) :: String.t()
  def normalize_identity(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  def normalize_identity(value), do: to_string(value)

  defp hash_key(key) do
    :crypto.hash(:sha256, normalize_identity(key))
  end
end
