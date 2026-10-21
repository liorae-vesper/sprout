defmodule Sprout.Land.Parcel do
  @moduledoc "Land available to the farm, independent of how it is cultivated."
  @type t :: %__MODULE__{}

  use Ecto.Schema
  import Ecto.Changeset

  schema "parcels" do
    field :name, :string
    field :area_ha, :float
    field :boundary, :map
    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates editable attributes; context-owned fields must already be present on the record.

  Returns a changeset without persisting it. Use the owning context for commands.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:name, :area_ha, :boundary])
    |> validate_required([:name, :area_ha, :boundary])
    |> validate_number(:area_ha, greater_than: 0)
    |> validate_change(:boundary, fn :boundary, boundary ->
      if Sprout.Land.valid_boundary?(boundary),
        do: [],
        else: [boundary: "must be a non-degenerate simple polygon of latitude/longitude points"]
    end)
  end
end
