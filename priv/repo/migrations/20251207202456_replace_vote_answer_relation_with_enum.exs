defmodule YouCongress.Repo.Migrations.ReplaceVoteAnswerRelationWithEnum do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:votes) do
      add :answer, :string
    end

    flush()

    # Migrate data
    execute """
    UPDATE votes
    SET answer = CASE
      WHEN a.response IN ('Strongly agree', 'Agree') THEN 'for'
      WHEN a.response IN ('Strongly disagree', 'Disagree') THEN 'against'
      ELSE 'abstain'
    END
    FROM answers a
    WHERE votes.answer_id = a.id
    """

    # Cleanup
    drop_if_exists unique_index(:votes, [:author_id, :voting_id, :answer_id])

    alter table(:votes) do
      remove :answer_id
      modify :answer, :string, null: false
    end

    create_if_not_exists unique_index(:votes, [:author_id, :voting_id])
  end

  def down do
    alter table(:votes) do
      add :answer_id, references(:answers, on_delete: :nothing)
    end

    flush()

    # We need to map back 'for', 'against', 'abstain' to some answer_id.
    # We will map to "Agree", "Disagree", "Abstain" respectively to be safe.
    # This requires looking up their IDs.

    execute """
    UPDATE votes
    SET answer_id = a.id
    FROM answers a
    WHERE
      (votes.answer = 'for' AND a.response = 'Agree') OR
      (votes.answer = 'against' AND a.response = 'Disagree') OR
      (votes.answer = 'abstain' AND a.response = 'Abstain') OR
      (votes.answer = 'abstain' AND a.response = 'N/A') OR
      (votes.answer IS NULL AND a.response IS NULL)
    """

    alter table(:votes) do
      remove :answer
    end

    create unique_index(:votes, [:author_id, :voting_id, :answer_id])
  end
end
