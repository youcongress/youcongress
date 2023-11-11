defmodule YouCongress.Repo.Migrations.CreateAuthors do
  use Ecto.Migration

  def change do
    create table(:authors) do
      add :name, :string
      add :bio, :text
      add :wikipedia_url, :string, unique: true
      add :twitter_url, :string, unique: true
      add :country, :string
      add :is_twin, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:authors, [:twitter_url])
    create unique_index(:authors, [:wikipedia_url])
  end
end
