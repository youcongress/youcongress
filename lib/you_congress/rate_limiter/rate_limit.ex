defmodule YouCongress.RateLimiter.RateLimit do
  @moduledoc false

  use Ecto.Schema

  schema "rate_limits" do
    field :scope, :string
    field :key_hash, :binary
    field :bucket_start, :utc_datetime
    field :count, :integer

    timestamps()
  end
end
