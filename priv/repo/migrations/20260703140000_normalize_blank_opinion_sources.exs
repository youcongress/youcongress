defmodule YouCongress.Repo.Migrations.NormalizeBlankOpinionSources do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE opinions
    SET source_url = NULL
    WHERE source_url IS NOT NULL AND btrim(source_url) = ''
    """)

    execute("""
    UPDATE opinions
    SET source_text = NULL
    WHERE source_text IS NOT NULL AND btrim(source_text) = ''
    """)
  end

  def down do
    :ok
  end
end
