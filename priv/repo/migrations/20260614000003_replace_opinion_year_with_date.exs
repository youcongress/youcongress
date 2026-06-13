defmodule YouCongress.Repo.Migrations.ReplaceOpinionYearWithDate do
  use Ecto.Migration

  def up do
    alter table(:opinions) do
      add :date, :date
      add :date_precision, :string
    end

    flush()

    execute """
    UPDATE opinions
    SET date = make_date(year, 1, 1),
        date_precision = 'year'
    WHERE year IS NOT NULL
    """

    create index(:opinions, [:date])

    create constraint(:opinions, :date_requires_valid_precision,
             check:
               "(date IS NULL AND date_precision IS NULL) OR " <>
                 "(date IS NOT NULL AND date_precision IN ('day', 'month', 'year'))"
           )

    drop_if_exists index(:opinions, [:year])

    alter table(:opinions) do
      remove :year
    end
  end

  def down do
    alter table(:opinions) do
      add :year, :integer
    end

    flush()

    execute """
    UPDATE opinions
    SET year = EXTRACT(YEAR FROM date)::integer
    WHERE date IS NOT NULL
    """

    create index(:opinions, [:year])
    drop constraint(:opinions, :date_requires_valid_precision)
    drop_if_exists index(:opinions, [:date])

    alter table(:opinions) do
      remove :date
      remove :date_precision
    end
  end
end
