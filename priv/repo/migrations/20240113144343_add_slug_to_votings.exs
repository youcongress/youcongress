defmodule YouCongress.Repo.Migrations.AddSlugToVotings do
  use Ecto.Migration

  def change do
    alter table(:votings) do
      add :slug, :string
    end

    create unique_index(:votings, [:slug])
  end
end
