defmodule YouCongress.Cache do
  @moduledoc """
  Tiny ETS-backed cache with a per-entry TTL.

  The table is owned by this process so it lives and dies with the supervision
  tree. Entries are per-node (not shared across the cluster), which is fine for
  memoising expensive-but-reproducible computations like the dataset export.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc """
  Returns the cached value for `key` if it hasn't expired, otherwise computes it
  with `fun`, stores it for `ttl_ms` milliseconds and returns it.
  """
  @spec fetch(term, non_neg_integer, (-> value)) :: value when value: term
  def fetch(key, ttl_ms, fun) when is_function(fun, 0) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        value

      _ ->
        value = fun.()
        :ets.insert(@table, {key, value, now + ttl_ms})
        value
    end
  end

  @doc "Removes a cached entry."
  @spec delete(term) :: :ok
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end
end
