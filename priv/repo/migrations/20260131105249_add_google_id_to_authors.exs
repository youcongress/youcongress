defmodule YouCongress.Repo.Migrations.AddGoogleIdToAuthors do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :google_id, :string
    end

    create unique_index(:authors, [:google_id])
  end
end
