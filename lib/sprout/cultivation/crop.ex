defmodule Sprout.Cultivation.Crop do
  @moduledoc "A field’s crop cycle. State and ownership are controlled by `Sprout.Cultivation`."
  @type t :: %__MODULE__{}

  use Ecto.Schema
  import Ecto.Changeset

  schema "crops" do
    field :field_id, :id
    field :name, :string
    field :variety, :string
    field :baseline_kg_ha, :float
    field :planned_on, :date
    field :planted_on, :date
    field :harvested_on, :date

    field :status, Ecto.Enum,
      values: [:planned, :growing, :harvested, :cancelled],
      default: :planned

    field :lock_version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates editable attributes; context-owned fields must already be present on the record.

  Returns a changeset without persisting it. Use the owning context for commands.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:name, :variety, :baseline_kg_ha, :planned_on])
    |> validate_required([:field_id, :name, :variety, :baseline_kg_ha, :planned_on, :status])
    |> validate_number(:baseline_kg_ha, greater_than: 0)
    |> foreign_key_constraint(:field_id)
    |> unique_constraint(:field_id,
      name: :one_planned_crop,
      message: "already has a next crop planned"
    )
    |> unique_constraint(:field_id,
      name: :one_growing_crop,
      message: "already has a growing crop"
    )
  end
end
