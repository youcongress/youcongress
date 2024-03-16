defmodule YouCongress.Repo.Migrations.RenameAuthorsEnabledToTwinEnabled do
  use Ecto.Migration

  def change do
    rename table(:authors), :enabled, to: :twin_enabled
  end
end
