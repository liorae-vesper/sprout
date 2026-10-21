defmodule Sprout.Equipment.Asset do
  @moduledoc "Equipment assigned to a field with an explicit kind and availability state."
  @type t :: %__MODULE__{}

  use Ecto.Schema
  import Ecto.Changeset

  schema "assets" do
    field :field_id, :id
    field :name, :string
    field :kind, Ecto.Enum, values: [:pump, :tractor, :sensor, :tool]
    field :status, Ecto.Enum, values: [:ready, :maintenance, :offline]
    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates editable attributes; context-owned fields must already be present on the record.

  Returns a changeset without persisting it. Use the owning context for commands.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:name, :kind, :status])
    |> validate_required([:field_id, :name, :kind, :status])
    |> validate_length(:name, max: 100)
    |> foreign_key_constraint(:field_id)
  end
end
