defmodule YouCongress.Repo.Migrations.AllowNullEmailForXRegistration do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :email, :string, null: true, from: {:string, null: false}
    end
  end
end
