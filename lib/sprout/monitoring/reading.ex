defmodule Sprout.Monitoring.Reading do
  @moduledoc "An immutable telemetry sample with explicit units and a manual, simulated, or physical-device source."
  @type t :: %__MODULE__{}

  use Ecto.Schema
  import Ecto.Changeset

  schema "readings" do
    field :field_id, :id
    field :moisture, :float
    field :temperature, :float
    field :humidity, :float
    field :water_l, :float
    field :source, Ecto.Enum, values: [:manual, :simulated, :device], default: :manual
    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates editable attributes; context-owned fields must already be present on the record.

  Returns a changeset without persisting it. Use the owning context for commands.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:moisture, :temperature, :humidity, :water_l, :source])
    |> validate_required([:field_id, :moisture, :temperature, :humidity, :water_l, :source])
    |> validate_number(:moisture, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:humidity, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:temperature, greater_than_or_equal_to: -50, less_than_or_equal_to: 70)
    |> validate_number(:water_l, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:field_id)
  end
end
