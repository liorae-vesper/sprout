defmodule Sprout.Repo.Migrations.CreateFarm do
  use Ecto.Migration

  def change do
    create table(:fields) do
      add :name, :text, null: false
      add :area_ha, :float, null: false
      add :boundary, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create constraint(:fields, :positive_area, check: "area_ha > 0")

    create table(:crops) do
      add :field_id, references(:fields), null: false
      add :name, :text, null: false
      add :variety, :text, null: false
      add :baseline_kg_ha, :float, null: false
      add :planted_on, :date, null: false
      add :status, :text, null: false, default: "planned"
      add :lock_version, :integer, default: 1, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:crops, [:field_id],
             where: "status IN ('planned', 'growing')",
             name: :one_active_crop
           )

    create constraint(:crops, :crop_status, check: "status IN ('planned','growing','harvested')")
    create constraint(:crops, :positive_baseline, check: "baseline_kg_ha > 0")

    create table(:readings) do
      add :field_id, references(:fields), null: false
      add :moisture, :float, null: false
      add :temperature, :float, null: false
      add :humidity, :float, null: false
      add :water_l, :float, null: false
      add :source, :text, null: false, default: "manual"
      timestamps(type: :utc_datetime)
    end

    create index(:readings, [:field_id, :inserted_at])

    create constraint(:readings, :reading_ranges,
             check:
               "moisture BETWEEN 0 AND 100 AND humidity BETWEEN 0 AND 100 AND temperature BETWEEN -50 AND 70 AND water_l >= 0"
           )

    create table(:findings) do
      add :field_id, references(:fields), null: false
      add :kind, :text, null: false
      add :severity, :float, null: false
      add :notes, :text, null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :status, :text, null: false, default: "open"
      timestamps(type: :utc_datetime)
    end

    create constraint(:findings, :severity_range, check: "severity BETWEEN 0 AND 1")

    create table(:assets) do
      add :field_id, references(:fields), null: false
      add :name, :text, null: false
      add :kind, :text, null: false
      add :status, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:photos) do
      add :field_id, references(:fields), null: false
      add :filename, :text, null: false
      add :storage_key, :text, null: false
      add :sha256, :text, null: false
      add :status, :text, null: false, default: "awaiting_model"
      add :result, :map
      timestamps(type: :utc_datetime)
    end

    create unique_index(:photos, [:storage_key])
  end
end
