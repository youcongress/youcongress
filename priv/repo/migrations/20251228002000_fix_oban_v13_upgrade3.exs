defmodule YouCongress.Repo.Migrations.FixObanV13Upgrade3 do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 13)
  end

  def down do
    Oban.Migration.down(version: 12)
  end
end
