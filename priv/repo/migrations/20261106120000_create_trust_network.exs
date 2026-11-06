defmodule YouCongress.Repo.Migrations.CreateTrustNetwork do
  use Ecto.Migration

  def change do
    create table(:councils) do
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :version, :integer, null: false, default: 1
      add :published, :boolean, null: false, default: false
      add :digest, :string, null: false, default: "off"
      timestamps()
    end

    create unique_index(:councils, [:author_id])

    create table(:council_lists) do
      add :council_id, references(:councils, on_delete: :delete_all), null: false
      add :hall_id, references(:halls, on_delete: :restrict)
      add :name, :string, null: false
      add :position, :integer, null: false
      add :fallback, :boolean, null: false, default: false
      timestamps()
    end

    create index(:council_lists, [:council_id, :position])

    create unique_index(:council_lists, [:council_id],
             where: "fallback",
             name: :one_council_fallback
           )

    create constraint(:council_lists, :fallback_is_general,
             check: "NOT fallback OR hall_id IS NULL"
           )

    create table(:council_members) do
      add :list_id, references(:council_lists, on_delete: :delete_all), null: false
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :reason, :text
      add :source_url, :text
      timestamps()
    end

    create unique_index(:council_members, [:list_id, :author_id])
    create index(:council_members, [:author_id])

    create table(:council_decisions) do
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :statement_id, references(:statements, on_delete: :delete_all), null: false
      add :answer, :string
      add :council_version, :integer, null: false
      add :explanation, :map, null: false, default: %{}
      timestamps()
    end

    create unique_index(:council_decisions, [:author_id, :statement_id])

    alter table(:votes) do
      add :origin, :string, null: false, default: "legacy"
      add :cast_by_user_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:halls) do
      add :community_enabled, :boolean, null: false, default: false
      add :organizer_id, references(:users, on_delete: :nilify_all)
    end

    create table(:community_memberships) do
      add :hall_id, references(:halls, on_delete: :delete_all), null: false
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:community_memberships, [:hall_id, :author_id])

    create table(:trust_recommendations) do
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :nominee_id, references(:authors, on_delete: :delete_all), null: false
      add :scope, :string, null: false
      add :reason, :text
      add :source_url, :text
      add :published, :boolean, null: false, default: false
      timestamps()
    end

    create unique_index(:trust_recommendations, [:author_id, :nominee_id, :scope])

    create table(:trust_snapshots) do
      add :title, :string, null: false
      add :scope, :string, null: false
      add :filters, :map, null: false, default: %{}
      add :result, :map, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      timestamps(updated_at: false)
    end

    create table(:trust_requests) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :author_id, references(:authors, on_delete: :nilify_all)
      add :statement_id, references(:statements, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :body, :text, null: false
      add :source_url, :text
      add :status, :string, null: false, default: "open"
      add :resolution, :text
      add :attempts, {:array, :map}, null: false, default: []
      timestamps()
    end

    create index(:trust_requests, [:status, :inserted_at])

    create table(:trust_notifications) do
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :body, :text, null: false
      add :path, :text, null: false
      add :read_at, :naive_datetime
      add :emailed_at, :naive_datetime
      timestamps()
    end

    create unique_index(:trust_notifications, [:author_id, :key])

    alter table(:reconsideration_delegate_selections) do
      add :council_list_id, references(:council_lists, on_delete: :nilify_all)
      add :council_member_id, references(:council_members, on_delete: :nilify_all)
      add :created_membership, :boolean, null: false, default: false
    end

    alter table(:reconsideration_responses) do
      add :cast_vote_id, :bigint
      add :cast_vote_updated_at, :naive_datetime
    end
  end
end
