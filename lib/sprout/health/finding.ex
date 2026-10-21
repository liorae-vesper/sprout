defmodule Sprout.Health.Finding do
  @moduledoc "Geolocated scouting evidence with fractional severity and retained resolution state."
  @type t :: %__MODULE__{}

  use Ecto.Schema
  import Ecto.Changeset

  schema "findings" do
    field :field_id, :id
    field :kind, Ecto.Enum, values: [:pest, :disease, :nutrition]
    field :severity, :float
    field :notes, :string
    field :latitude, :float
    field :longitude, :float
    field :status, Ecto.Enum, values: [:open, :resolved], default: :open
    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates editable attributes; context-owned fields must already be present on the record.

  Returns a changeset without persisting it. Use the owning context for commands.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:kind, :severity, :notes, :latitude, :longitude])
    |> validate_required([:field_id, :kind, :severity, :notes, :latitude, :longitude, :status])
    |> validate_number(:severity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_length(:notes, min: 3, max: 1000)
    |> foreign_key_constraint(:field_id)
  end
end
