defmodule YouCongress.Repo.Migrations.AddSourceToVotes do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      add :source_url, :string
    end
  end
end
