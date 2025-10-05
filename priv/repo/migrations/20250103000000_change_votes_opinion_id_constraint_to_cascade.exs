defmodule YouCongress.Repo.Migrations.ChangeVotesOpinionIdConstraintToCascade do
  use Ecto.Migration

  def up do
    # Drop the existing foreign key constraint
    drop constraint(:votes, :votes_opinion_id_fkey)

    # Add the new foreign key constraint with CASCADE
    alter table(:votes) do
      modify :opinion_id, references(:opinions, on_delete: :delete_all)
    end
  end

  def down do
    # Drop the CASCADE constraint
    drop constraint(:votes, :votes_opinion_id_fkey)

    # Add back the original SET NULL constraint
    alter table(:votes) do
      modify :opinion_id, references(:opinions, on_delete: :nilify_all)
    end
  end
end
