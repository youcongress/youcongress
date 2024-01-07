defmodule YouCongress.Repo.Migrations.AddTwitterColumnsToAuthors do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :twitter_id_str, :string
      add :profile_image_url, :string
      add :description, :string
      add :followers_count, :integer
      add :verified, :boolean
      add :location, :string
    end

    create unique_index(:authors, [:twitter_id_str])
  end
end
