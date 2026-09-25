defmodule YouCongress.Repo.Migrations.CreateReconsiderationDelegateSelections do
  use Ecto.Migration

  def change do
    create table(:reconsideration_delegate_selections) do
      add :reconsideration_id, references(:reconsiderations, on_delete: :delete_all), null: false
      add :participant_author_id, references(:authors, on_delete: :delete_all), null: false
      add :delegate_author_id, references(:authors, on_delete: :restrict), null: false

      timestamps(updated_at: false)
    end

    create unique_index(
             :reconsideration_delegate_selections,
             [:reconsideration_id, :participant_author_id, :delegate_author_id],
             name: :reconsideration_delegate_selections_unique_index
           )

    create index(
             :reconsideration_delegate_selections,
             [
               :reconsideration_id,
               :delegate_author_id
             ], name: :reconsideration_delegate_selections_lookup_index)
  end
end
