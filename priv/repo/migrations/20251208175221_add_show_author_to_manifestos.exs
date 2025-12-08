defmodule YouCongress.Repo.Migrations.AddShowAuthorToManifestos do
  use Ecto.Migration

  def change do
    alter table(:manifestos) do
      add :show_author, :boolean, default: true, null: false
    end
  end
end
