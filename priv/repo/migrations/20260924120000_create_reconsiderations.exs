defmodule YouCongress.Repo.Migrations.CreateReconsiderations do
  use Ecto.Migration

  def change do
    create table(:reconsiderations) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :content_url, :text, null: false
      add :content_type, :string, null: false
      add :creator_id, references(:authors, on_delete: :delete_all), null: false
      add :published, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:reconsiderations, [:slug])
    create index(:reconsiderations, [:creator_id])

    create table(:reconsideration_statements) do
      add :reconsideration_id, references(:reconsiderations, on_delete: :delete_all), null: false
      add :statement_id, references(:statements, on_delete: :restrict), null: false
      add :statement_title, :text, null: false
      add :position, :integer, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:reconsideration_statements, [:reconsideration_id, :statement_id],
             name: :reconsideration_statements_campaign_statement_index
           )

    create unique_index(:reconsideration_statements, [:reconsideration_id, :position])
    create index(:reconsideration_statements, [:statement_id])

    create table(:reconsideration_delegates) do
      add :reconsideration_id, references(:reconsiderations, on_delete: :delete_all), null: false
      add :author_id, references(:authors, on_delete: :restrict), null: false
      add :position, :integer, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:reconsideration_delegates, [:reconsideration_id, :author_id])
    create unique_index(:reconsideration_delegates, [:reconsideration_id, :position])
    create index(:reconsideration_delegates, [:author_id])

    create table(:reconsideration_responses) do
      add :reconsideration_id, references(:reconsiderations, on_delete: :delete_all), null: false
      add :statement_id, references(:statements, on_delete: :restrict), null: false
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :before_answer, :string, null: false
      add :after_answer, :string, null: false

      timestamps()
    end

    create unique_index(
             :reconsideration_responses,
             [:reconsideration_id, :statement_id, :author_id],
             name: :reconsideration_responses_campaign_statement_author_index
           )

    create index(:reconsideration_responses, [:reconsideration_id, :author_id])
    create index(:reconsideration_responses, [:statement_id])
  end
end
