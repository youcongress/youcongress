defmodule YouCongress.Repo.Migrations.AddSourceTextToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :source_text, :text
    end
  end
end
