defmodule YouCongress.Repo.Migrations.AddContentEmbeddingToOpinions do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    alter table(:opinions) do
      add :content_embedding, :vector, size: 1536
    end

    execute """
    CREATE INDEX opinions_content_embedding_hnsw_cosine_index
    ON opinions USING hnsw (content_embedding vector_cosine_ops)
    WHERE content_embedding IS NOT NULL
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS opinions_content_embedding_hnsw_cosine_index"

    alter table(:opinions) do
      remove :content_embedding
    end
  end
end
