defmodule YouCongress.Repo.Migrations.AddSignupMethodToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :signup_method, :string
    end
  end
end
