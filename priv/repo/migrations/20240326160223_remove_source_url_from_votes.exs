defmodule YouCongress.Repo.Migrations.RemoveSourceUrlFromVotes do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      remove :source_url
    end
  end
end
