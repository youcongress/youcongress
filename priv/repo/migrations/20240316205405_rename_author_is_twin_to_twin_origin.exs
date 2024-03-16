defmodule YouCongress.Repo.Migrations.RenameAuthorIsTwinToTwinOrigin do
  use Ecto.Migration

  def change do
    rename table(:authors), :is_twin, to: :twin_origin
  end
end
