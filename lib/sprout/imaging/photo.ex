defmodule Sprout.Imaging.Photo do
  @moduledoc "Private original-photo metadata and persisted inference-processing state."
  @type t :: %__MODULE__{}

  use Ecto.Schema
  import Ecto.Changeset

  schema "photos" do
    field :field_id, :id
    field :filename, :string
    field :storage_key, :string
    field :sha256, :string

    field :status, Ecto.Enum,
      values: [:awaiting_model, :processing, :completed, :failed],
      default: :awaiting_model

    field :result, :map
    timestamps(type: :utc_datetime)
  end

  @doc """
  Validates editable attributes; context-owned fields must already be present on the record.

  Returns a changeset without persisting it. Use the owning context for commands.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:filename, :storage_key, :sha256])
    |> validate_required([:field_id, :filename, :storage_key, :sha256, :status])
    |> foreign_key_constraint(:field_id)
  end
end
