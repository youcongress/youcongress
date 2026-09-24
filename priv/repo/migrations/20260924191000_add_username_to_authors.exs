defmodule YouCongress.Repo.Migrations.AddUsernameToAuthors do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :username, :string
    end

    create unique_index(:authors, ["lower(username)"], name: :authors_username_index)
  end
end
