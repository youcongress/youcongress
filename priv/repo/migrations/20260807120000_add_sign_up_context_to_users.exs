defmodule YouCongress.Repo.Migrations.AddSignUpContextToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :sign_up_context, :map
    end
  end
end
