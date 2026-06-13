defmodule YouCongress.Repo.Migrations.MakeVerificationCommentsNullable do
  use Ecto.Migration

  def change do
    alter table(:verifications) do
      modify :comment, :text, null: true, from: {:text, null: false}
    end

    alter table(:opinion_statement_verifications) do
      modify :comment, :text, null: true, from: {:text, null: false}
    end

    alter table(:vote_verifications) do
      modify :comment, :text, null: true, from: {:text, null: false}
    end
  end
end
