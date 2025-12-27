defmodule YouCongress.Repo.Migrations.FixObanV13Upgrade2 do
  use Ecto.Migration

  def up do
    create_if_not_exists table(:oban_peers) do
      add :name, :text, primary_key: true
      add :node, :text
      add :started_at, :naive_datetime
      add :expires_at, :naive_datetime
    end

    Oban.Migration.down(version: 11)

    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 11)
  end
end
