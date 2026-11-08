defmodule YouCongress.Repo.Migrations.AddCouncilOnboarding do
  use Ecto.Migration

  def up do
    alter table(:councils) do
      add :onboarding_completed, :boolean, default: false, null: false
    end

    flush()
    execute "UPDATE councils SET onboarding_completed = TRUE"
  end

  def down do
    alter table(:councils) do
      remove :onboarding_completed
    end
  end
end
