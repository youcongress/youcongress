defmodule YouCongress.Repo.Migrations.VersionTrustEvidence do
  use Ecto.Migration

  def change do
    for table_name <- [
          :opinions,
          :verifications,
          :opinion_statement_verifications,
          :vote_verifications
        ] do
      alter table(table_name) do
        add :evidence_revision, :integer, null: false, default: 1
      end
    end
  end
end
