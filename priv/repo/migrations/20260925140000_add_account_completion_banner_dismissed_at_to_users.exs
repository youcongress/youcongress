defmodule YouCongress.Repo.Migrations.AddAccountCompletionBannerDismissedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :account_completion_banner_dismissed_at, :naive_datetime
    end
  end
end
