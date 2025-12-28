defmodule YouCongress.Repo.Migrations.FixObanPeersPk do
  use Ecto.Migration

  def up do
    # 1. Drop the table with the restrictive single-column PK
    drop_if_exists table(:oban_peers)

    # 2. Recreate with Composite Primary Key (name, node)
    create table(:oban_peers, primary_key: false) do
      add :name, :text, primary_key: true
      add :node, :text, primary_key: true
      add :started_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    # Ensure version tracking is correct
    execute "COMMENT ON TABLE public.oban_jobs IS '13'"
  end

  def down do
    # No real down needed as this is a fix-forward, but we can drop
    drop table(:oban_peers)
  end
end
