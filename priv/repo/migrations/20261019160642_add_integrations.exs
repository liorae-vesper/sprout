defmodule Sprout.Repo.Migrations.AddIntegrations do
  use Ecto.Migration

  def change do
    create table(:integration_clients) do
      add :name, :text, null: false
      add :scopes, {:array, :text}, null: false
      add :token_digest, :binary, null: false
      add :token_prefix, :text, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:integration_clients, [:token_digest])

    create table(:integration_fields, primary_key: false) do
      add :client_id, references(:integration_clients, on_delete: :delete_all), primary_key: true
      add :field_id, references(:fields, on_delete: :delete_all), primary_key: true
    end

    create table(:integration_requests) do
      add :client_id, references(:integration_clients), null: false
      add :key, :text, null: false
      add :payload_digest, :binary, null: false
      add :reading_id, references(:readings), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:integration_requests, [:client_id, :key])
  end
end
