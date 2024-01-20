defmodule YouCongress.Repo.Migrations.AddFriendsCountToAuthors do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :friends_count, :integer
    end
  end
end
