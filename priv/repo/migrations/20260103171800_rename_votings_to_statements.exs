defmodule YouCongress.Repo.Migrations.RenameVotingsToStatements do
  use Ecto.Migration

  def change do
    # Rename main votings table to statements
    rename table(:votings), to: table(:statements)

    # Rename halls_votings to halls_statements
    rename table(:halls_votings), to: table(:halls_statements)

    # Rename opinions_votings to opinions_statements
    rename table(:opinions_votings), to: table(:opinions_statements)

    # Rename voting_id columns to statement_id in all affected tables
    rename table(:votes), :voting_id, to: :statement_id
    rename table(:halls_statements), :voting_id, to: :statement_id
    rename table(:opinions_statements), :voting_id, to: :statement_id
  end
end
