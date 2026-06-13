defmodule YouCongress.Repo.Migrations.CreateVoteVerifications do
  use Ecto.Migration

  def change do
    create table(:vote_verifications) do
      add :vote_id, references(:votes, on_delete: :delete_all), null: false
      # opinion_id the vote referenced when verified. If the vote later points to a
      # newer opinion, prior verifications no longer apply and are ignored when caching.
      add :opinion_id, references(:opinions, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :comment, :text, null: false
      add :model, :string, default: "human"

      timestamps()
    end

    create index(:vote_verifications, [:vote_id])
    create index(:vote_verifications, [:opinion_id])
    create index(:vote_verifications, [:user_id])

    alter table(:votes) do
      add :verification_status, :string
    end
  end
end
