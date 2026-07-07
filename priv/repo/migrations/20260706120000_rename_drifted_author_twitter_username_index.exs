defmodule YouCongress.Repo.Migrations.RenameDriftedAuthorTwitterUsernameIndex do
  @moduledoc """
  Realign the author X/Twitter username unique index after the column rename.

  Postgres kept the original `authors_twitter_url_index` name when
  `twitter_url` was renamed to `twitter_username`, but Ecto derives the
  expected unique constraint name from the current column name.
  """
  use Ecto.Migration

  def up do
    rename_index("authors_twitter_url_index", "authors_twitter_username_index")
  end

  def down do
    rename_index("authors_twitter_username_index", "authors_twitter_url_index")
  end

  defp rename_index(from, to) do
    execute(~s(ALTER INDEX IF EXISTS "#{from}" RENAME TO "#{to}"))
  end
end
