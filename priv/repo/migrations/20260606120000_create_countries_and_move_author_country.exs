defmodule YouCongress.Repo.Migrations.CreateCountriesAndMoveAuthorCountry do
  use Ecto.Migration

  def up do
    create table(:countries) do
      add :name, :string, null: false
      add :iso_alpha2, :string
      add :iso_alpha3, :string
      add :phone_prefix, :string

      timestamps()
    end

    create unique_index(:countries, [:name])
    create unique_index(:countries, [:iso_alpha2], where: "iso_alpha2 IS NOT NULL")
    create unique_index(:countries, [:iso_alpha3], where: "iso_alpha3 IS NOT NULL")

    alter table(:authors) do
      add :country_id, references(:countries, on_delete: :nilify_all)
    end

    create index(:authors, [:country_id])

    execute("""
    WITH mapped_author_countries AS (
      SELECT DISTINCT
        #{normalized_country_name_sql()} AS name,
        #{normalized_country_iso2_sql()} AS iso_alpha2,
        #{normalized_country_iso3_sql()} AS iso_alpha3
      FROM authors
      WHERE country IS NOT NULL AND btrim(country) <> ''
    )
    INSERT INTO countries (name, iso_alpha2, iso_alpha3, inserted_at, updated_at)
    SELECT name, iso_alpha2, iso_alpha3, now(), now()
    FROM mapped_author_countries
    ON CONFLICT (name) DO UPDATE SET
      iso_alpha2 = COALESCE(countries.iso_alpha2, EXCLUDED.iso_alpha2),
      iso_alpha3 = COALESCE(countries.iso_alpha3, EXCLUDED.iso_alpha3),
      updated_at = now()
    """)

    execute("""
    UPDATE authors
    SET country_id = countries.id
    FROM countries
    WHERE countries.name = #{normalized_country_name_sql()}
    """)

    alter table(:authors) do
      remove :country
    end
  end

  def down do
    alter table(:authors) do
      add :country, :string
    end

    execute("""
    UPDATE authors
    SET country = countries.name
    FROM countries
    WHERE authors.country_id = countries.id
    """)

    drop index(:authors, [:country_id])

    alter table(:authors) do
      remove :country_id
    end

    drop table(:countries)
  end

  defp normalized_country_name_sql do
    """
    CASE lower(btrim(country))
      WHEN 'us' THEN 'United States'
      WHEN 'usa' THEN 'United States'
      WHEN 'united states of america' THEN 'United States'
      WHEN 'gb' THEN 'United Kingdom'
      WHEN 'ca' THEN 'Canada'
      ELSE btrim(country)
    END
    """
  end

  defp normalized_country_iso2_sql do
    """
    CASE lower(btrim(country))
      WHEN 'us' THEN 'US'
      WHEN 'usa' THEN 'US'
      WHEN 'united states' THEN 'US'
      WHEN 'united states of america' THEN 'US'
      WHEN 'gb' THEN 'GB'
      WHEN 'united kingdom' THEN 'GB'
      WHEN 'ca' THEN 'CA'
      WHEN 'canada' THEN 'CA'
      ELSE NULL
    END
    """
  end

  defp normalized_country_iso3_sql do
    """
    CASE lower(btrim(country))
      WHEN 'us' THEN 'USA'
      WHEN 'usa' THEN 'USA'
      WHEN 'united states' THEN 'USA'
      WHEN 'united states of america' THEN 'USA'
      WHEN 'gb' THEN 'GBR'
      WHEN 'united kingdom' THEN 'GBR'
      WHEN 'ca' THEN 'CAN'
      WHEN 'canada' THEN 'CAN'
      ELSE NULL
    END
    """
  end
end
