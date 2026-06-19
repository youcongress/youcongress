defmodule YouCongress.Repo.Migrations.AddWikidataToAuthors do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :wikidata, :string
    end
  end
end
