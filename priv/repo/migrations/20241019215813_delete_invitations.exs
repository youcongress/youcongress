defmodule YouCongress.Repo.Migrations.DeleteInvitations do
  use Ecto.Migration

  def change do
    drop table(:invitations)
  end
end
