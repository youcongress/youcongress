defmodule YouCongress.Repo.Migrations.AddPhoneConfirmedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :phone_number_confirmed_at, :utc_datetime
    end
  end
end
