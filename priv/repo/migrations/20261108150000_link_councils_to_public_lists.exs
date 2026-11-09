defmodule YouCongress.Repo.Migrations.LinkCouncilsToPublicLists do
  use Ecto.Migration

  def change do
    create table(:council_public_list_links, primary_key: false) do
      add :author_id, references(:authors, on_delete: :delete_all), primary_key: true
      add :people_list_id, references(:people_lists, on_delete: :delete_all), null: false
    end

    create unique_index(:council_public_list_links, [:people_list_id])
  end
end
