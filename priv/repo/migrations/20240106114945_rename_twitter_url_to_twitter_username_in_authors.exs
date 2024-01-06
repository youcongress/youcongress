defmodule YouCongress.Repo.Migrations.RenameTwitterUrlToTwitterUsernameInAuthors do
  use Ecto.Migration

  def up do
    rename table(:authors), :twitter_url, to: :twitter_username
  end

  def down do
    rename table(:authors), :twitter_username, to: :twitter_url
  end
end
