defmodule Sprout.Repo.Migrations.SeparateParcelsPlotsAndCycles do
  use Ecto.Migration

  def up do
    audit_legacy_boundaries!()

    create table(:parcels) do
      add :name, :text, null: false
      add :area_ha, :float, null: false
      add :boundary, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create constraint(:parcels, :parcel_positive_area, check: "area_ha > 0")

    alter table(:fields) do
      add :parcel_id, references(:parcels)
      add :soil_status, :text, null: false, default: "resting"
      add :lock_version, :integer, null: false, default: 1
    end

    flush()

    execute "INSERT INTO parcels (id, name, area_ha, boundary, inserted_at, updated_at) SELECT id, name, area_ha, boundary, inserted_at, updated_at FROM fields"

    execute "SELECT setval(pg_get_serial_sequence('parcels', 'id'), COALESCE(MAX(id), 1), COUNT(*) > 0) FROM parcels"

    execute "UPDATE fields SET parcel_id = id, soil_status = CASE WHEN EXISTS (SELECT 1 FROM crops WHERE crops.field_id = fields.id AND crops.status = 'growing') THEN 'ready' ELSE 'resting' END"

    alter table(:fields), do: modify(:parcel_id, :bigint, null: false)
    create index(:fields, [:parcel_id])

    create constraint(:fields, :plot_soil_status,
             check: "soil_status IN ('resting', 'preparing', 'ready')"
           )

    rename table(:crops), :planted_on, to: :planned_on

    alter table(:crops) do
      add :planted_on, :date
      add :harvested_on, :date
    end

    execute "UPDATE crops SET planted_on = planned_on WHERE status IN ('growing', 'harvested')"
    drop index(:crops, [:field_id], name: :one_active_crop)
    drop constraint(:crops, :crop_status)
    create unique_index(:crops, [:field_id], where: "status = 'planned'", name: :one_planned_crop)
    create unique_index(:crops, [:field_id], where: "status = 'growing'", name: :one_growing_crop)

    create constraint(:crops, :crop_status,
             check: "status IN ('planned','growing','harvested','cancelled')"
           )
  end

  # Refuse to invent overlapping land holdings from previously unconstrained fields.
  defp audit_legacy_boundaries! do
    rows = repo().query!("SELECT id, boundary FROM fields", []).rows

    Enum.each(rows, fn [id, boundary] ->
      unless Sprout.Land.valid_boundary?(boundary),
        do: raise("Legacy field #{id} has an invalid boundary; correct it before migrating")

      Enum.each(rows, fn [other, neighbor] ->
        if other > id and Sprout.Land.Geometry.overlap?(boundary["points"], neighbor["points"]),
          do:
            raise(
              "Legacy fields #{id} and #{other} overlap; correct their boundaries before migrating"
            )
      end)
    end)
  end

  def down do
    raise "Cannot collapse parcels, plots and queued cycles without losing domain data. Restore a backup instead."
  end
end
