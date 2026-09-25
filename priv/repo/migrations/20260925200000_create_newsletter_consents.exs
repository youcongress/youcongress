defmodule YouCongress.Repo.Migrations.CreateNewsletterConsents do
  use Ecto.Migration

  def change do
    create table(:newsletter_consents) do
      add :email, :citext, null: false
      add :action, :string, null: false
      add :source, :string, null: false
      add :token_hash, :binary
      add :expires_at, :utc_datetime
      add :confirmed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create index(:newsletter_consents, [:email, :confirmed_at])
    create unique_index(:newsletter_consents, [:token_hash], where: "token_hash IS NOT NULL")
    create index(:newsletter_consents, [:user_id])
  end
end
