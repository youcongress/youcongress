defmodule YouCongress.Repo.Migrations.RenameDriftedStatementIndexes do
  @moduledoc """
  Realign index/constraint names that drifted after `20260103171800_rename_votings_to_statements`.

  Postgres does NOT rename an index/constraint when its table or column is renamed, so the DB
  still carries `votings_*` / `*_voting_id_*` names while the Ecto changesets compute the new
  default names (`statements_*`, `*_statement_id_*`). That mismatch makes duplicate-insert races
  and FK violations raise `Ecto.ConstraintError` instead of returning `{:error, changeset}`.

  This migration renames the drifted objects to the names Ecto expects. Pure renames, no data
  change. Pkeys (`votings_pkey`) and sequences (`votings_id_seq`) are intentionally left out —
  no changeset references them, so renaming them would add risk without benefit.
  """
  use Ecto.Migration

  # {old_name, new_name}
  @index_renames [
    # correctness-critical: backed by unique_constraint calls in the schemas
    {"votings_title_index", "statements_title_index"},
    {"votings_slug_index", "statements_slug_index"},
    {"votes_author_id_voting_id_index", "votes_author_id_statement_id_index"},
    {"opinions_votings_opinion_id_voting_id_index",
     "opinions_statements_opinion_id_statement_id_index"},
    # consistency: remaining drifted indexes
    {"votings_title_trgm_index", "statements_title_trgm_index"},
    {"votes_voting_id_index", "votes_statement_id_index"},
    {"opinions_votings_voting_id_index", "opinions_statements_statement_id_index"},
    {"opinions_votings_user_id_index", "opinions_statements_user_id_index"},
    {"halls_votings_hall_id_voting_id_index", "halls_statements_hall_id_statement_id_index"},
    {"halls_votings_voting_id_index", "halls_statements_statement_id_index"},
    {"halls_votings_hall_id_index", "halls_statements_hall_id_index"}
  ]

  # {table, old_name, new_name}
  @constraint_renames [
    # correctness-critical: backed by foreign_key_constraint calls in opinion_statement.ex
    {"opinions_statements", "opinions_votings_opinion_id_fkey",
     "opinions_statements_opinion_id_fkey"},
    {"opinions_statements", "opinions_votings_voting_id_fkey",
     "opinions_statements_statement_id_fkey"},
    {"opinions_statements", "opinions_votings_user_id_fkey", "opinions_statements_user_id_fkey"},
    # consistency: remaining drifted FK constraints
    {"votes", "votes_voting_id_fkey", "votes_statement_id_fkey"},
    {"halls_statements", "halls_votings_voting_id_fkey", "halls_statements_statement_id_fkey"},
    {"halls_statements", "halls_votings_hall_id_fkey", "halls_statements_hall_id_fkey"}
  ]

  def up do
    Enum.each(@index_renames, fn {old, new} -> rename_index(old, new) end)
    Enum.each(@constraint_renames, fn {table, old, new} -> rename_constraint(table, old, new) end)
  end

  def down do
    Enum.each(@index_renames, fn {old, new} -> rename_index(new, old) end)
    Enum.each(@constraint_renames, fn {table, old, new} -> rename_constraint(table, new, old) end)
  end

  # ALTER INDEX supports IF EXISTS, so a no-op is safe when the source name is absent.
  # `up`/`down` are explicit, so use execute/1 and let each direction pass its own from/to.
  defp rename_index(from, to) do
    execute(~s(ALTER INDEX IF EXISTS "#{from}" RENAME TO "#{to}"))
  end

  # ALTER TABLE ... RENAME CONSTRAINT has no IF EXISTS, so guard on pg_constraint to stay idempotent.
  defp rename_constraint(table, from, to) do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '#{from}')
         AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '#{to}') THEN
        ALTER TABLE "#{table}" RENAME CONSTRAINT "#{from}" TO "#{to}";
      END IF;
    END $$;
    """)
  end
end
