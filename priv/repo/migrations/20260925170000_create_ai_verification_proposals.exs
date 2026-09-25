defmodule YouCongress.Repo.Migrations.CreateAIVerificationProposals do
  use Ecto.Migration

  def change do
    create table(:ai_verification_proposals) do
      add :subject, :string, null: false
      add :subject_id, :bigint, null: false
      add :subject_snapshot, :map, null: false
      add :result, :map, null: false
      add :request_options, :map, null: false, default: %{}
      add :model, :string, null: false
      add :review_status, :string, null: false, default: "pending"
      add :reviewed_at, :utc_datetime

      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :reviewer_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:ai_verification_proposals, [:subject, :subject_id])
    create index(:ai_verification_proposals, [:review_status, :inserted_at])
    create index(:ai_verification_proposals, [:requested_by_id])
    create index(:ai_verification_proposals, [:reviewer_id])
  end
end
