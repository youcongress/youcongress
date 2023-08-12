defmodule YouCongress.Repo do
  use Ecto.Repo,
    otp_app: :you_congress,
    adapter: Ecto.Adapters.Postgres
end
