defmodule YouCongress.RateLimiterTest do
  use YouCongress.DataCase

  alias YouCongress.RateLimiter
  alias YouCongress.RateLimiter.RateLimit
  alias YouCongress.Repo
  alias YouCongress.Workers.RateLimitPrunerWorker

  test "enforces a limit through an atomic database counter" do
    assert RateLimiter.check(:login, "Person@Example.com ", 2, 3_600) == :ok
    assert RateLimiter.check(:login, "person@example.com", 2, 3_600) == :ok

    assert {:error, {:rate_limited, retry_after}} =
             RateLimiter.check(:login, "PERSON@example.com", 2, 3_600)

    assert retry_after in 1..3_600
    assert [%RateLimit{count: 3}] = Repo.all(RateLimit)
  end

  test "keeps scopes and identifiers independent" do
    assert RateLimiter.allowed?(:password_login, "one@example.com", 1, 3_600)
    refute RateLimiter.allowed?(:password_login, "one@example.com", 1, 3_600)

    assert RateLimiter.allowed?(:magic_link, "one@example.com", 1, 3_600)
    assert RateLimiter.allowed?(:password_login, "two@example.com", 1, 3_600)
  end

  test "stores only a hash of the identifier" do
    assert RateLimiter.allowed?(:password_reset, "private@example.com", 1, 3_600)

    [entry] = Repo.all(RateLimit)
    assert is_binary(entry.key_hash)
    assert byte_size(entry.key_hash) == 32
    refute entry.key_hash =~ "private@example.com"
  end

  test "scheduled pruning removes expired buckets" do
    assert RateLimiter.allowed?(:login, "old@example.com", 1, 3_600)

    old_bucket = DateTime.add(DateTime.utc_now(), -8, :day) |> DateTime.truncate(:second)
    Repo.update_all(RateLimit, set: [bucket_start: old_bucket])

    assert :ok = RateLimitPrunerWorker.perform(%Oban.Job{})
    assert Repo.all(RateLimit) == []
  end
end
