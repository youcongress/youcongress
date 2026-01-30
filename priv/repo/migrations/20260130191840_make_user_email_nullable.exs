defmodule YouCongress.Repo.Migrations.MakeUserEmailNullable do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :email, :string, null: true, from: {:string, null: false}
    end
  end
end
