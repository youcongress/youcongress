defmodule YouCongress.Repo.Migrations.AddNewsletterToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :newsletter, :boolean, default: false
    end
  end
end
