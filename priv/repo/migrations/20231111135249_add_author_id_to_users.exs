defmodule YouCongress.Repo.Migrations.AddAuthorIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :author_id, references(:authors, on_delete: :nilify_all), null: false
    end
  end
end
