defmodule YouCongress.Repo.Migrations.TrackReconsiderationOwnership do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      add :revision, :integer, null: false, default: 1
    end

    alter table(:reconsideration_responses) do
      add :cast_vote_revision, :integer
      add :previous_vote, :map
    end

    alter table(:reconsideration_delegate_selections) do
      add :council_version, :integer
    end
  end
end
