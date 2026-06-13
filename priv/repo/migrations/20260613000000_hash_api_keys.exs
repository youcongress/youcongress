defmodule YouCongress.Repo.Migrations.HashApiKeys do
  use Ecto.Migration

  def up do
    alter table(:api_keys) do
      add :token_hash, :binary
      add :token_prefix, :string
    end

    flush()
    backfill_token_hashes()
    drop_if_exists unique_index(:api_keys, [:token])

    alter table(:api_keys) do
      remove :token
      modify :token_hash, :binary, null: false
      modify :token_prefix, :string, null: false
    end

    create unique_index(:api_keys, [:token_hash])
  end

  def down do
    drop_if_exists unique_index(:api_keys, [:token_hash])

    alter table(:api_keys) do
      add :token, :string
    end

    flush()
    backfill_placeholder_tokens()

    alter table(:api_keys) do
      modify :token, :string, null: false
      remove :token_hash
      remove :token_prefix
    end

    create unique_index(:api_keys, [:token])
  end

  defp backfill_token_hashes do
    %{rows: rows} = repo().query!("SELECT id, token FROM api_keys", [])

    Enum.each(rows, fn [id, token] ->
      repo().query!(
        "UPDATE api_keys SET token_hash = $1, token_prefix = $2 WHERE id = $3",
        [:crypto.hash(:sha256, token), String.slice(token, 0, 8), id]
      )
    end)
  end

  defp backfill_placeholder_tokens do
    %{rows: rows} = repo().query!("SELECT id FROM api_keys", [])

    Enum.each(rows, fn [id] ->
      repo().query!("UPDATE api_keys SET token = $1 WHERE id = $2", [
        "restored-api-key-#{id}",
        id
      ])
    end)
  end
end
