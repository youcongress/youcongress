defmodule YouCongress.Repo.Migrations.NormalizeUserEmailIdentity do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS citext")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM users
        WHERE email IS NOT NULL
        GROUP BY lower(email)
        HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION 'cannot convert users.email to citext: duplicate emails differ only by case';
      END IF;
    END $$;
    """)

    execute("""
    ALTER TABLE users
      ALTER COLUMN email TYPE citext
      USING email::citext
    """)
  end

  def down do
    execute("""
    ALTER TABLE users
      ALTER COLUMN email TYPE varchar(255)
      USING email::text
    """)
  end
end
