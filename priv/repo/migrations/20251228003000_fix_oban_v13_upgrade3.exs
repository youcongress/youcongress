defmodule YouCongress.Repo.Migrations.FixObanV13Upgrade3 do
  use Ecto.Migration

  def up do
    # 1. Drop the malformed table (if exists)
    drop_if_exists table(:oban_peers)

    # 2. Manually create the table with strict Oban schema (NO ID column)
    create table(:oban_peers, primary_key: false) do
      add :name, :text, primary_key: true
      add :node, :text, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    # 3. Ensure version is set to 13 matches reality
    execute "COMMENT ON TABLE public.oban_jobs IS '13'"
  end

  def down do
    Oban.Migration.down(version: 11)
  end
end
