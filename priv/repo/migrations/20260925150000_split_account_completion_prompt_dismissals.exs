defmodule YouCongress.Repo.Migrations.SplitAccountCompletionPromptDismissals do
  use Ecto.Migration

  def change do
    rename table(:users), :account_completion_banner_dismissed_at,
      to: :phone_verification_prompt_dismissed_at

    alter table(:users) do
      add :newsletter_subscription_prompt_dismissed_at, :naive_datetime
    end
  end
end
