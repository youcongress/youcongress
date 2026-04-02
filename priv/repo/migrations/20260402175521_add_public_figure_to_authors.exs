defmodule YouCongress.Repo.Migrations.AddPublicFigureToAuthors do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :public_figure, :boolean, default: false, null: false
    end

    execute(
      "UPDATE authors SET public_figure = true WHERE id IN (SELECT DISTINCT author_id FROM opinions WHERE source_url IS NOT NULL)",
      "UPDATE authors SET public_figure = false"
    )
  end
end
