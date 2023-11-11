defmodule YouCongress.Repo.Migrations.AddAnswerIdToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :answer_id, :integer
    end
  end
end
