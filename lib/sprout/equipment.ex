defmodule Sprout.Equipment do
  @moduledoc "Field-assigned equipment and availability."
  import Ecto.Query
  alias Sprout.{Equipment.Asset, Repo}

  @doc """
  Lists field-assigned equipment in creation order.
  """
  @spec list_assets() :: [Asset.t()]
  def list_assets, do: Repo.all(from a in Asset, order_by: a.id)

  @doc """
  Registers a pump, tractor, sensor, or tool for the given field.

  Readiness must be `:ready`, `:maintenance`, or `:offline`; invalid input returns a changeset.
  """
  @spec create_asset(Sprout.Land.Plot.t(), map()) ::
          {:ok, Asset.t()} | {:error, Ecto.Changeset.t()}
  def create_asset(field, attrs),
    do:
      %Asset{field_id: field.id}
      |> Asset.changeset(Map.drop(attrs, [:field_id, "field_id"]))
      |> Repo.insert()
      |> Sprout.Events.saved(:asset)

  @doc """
  Changes availability and broadcasts on success.

  Invalid states return a changeset. Raises `Ecto.NoResultsError` for an unknown ID.
  """
  @spec set_status(integer() | String.t(), atom() | String.t()) ::
          {:ok, Asset.t()} | {:error, Ecto.Changeset.t()}
  def set_status(id, status),
    do:
      Repo.get!(Asset, id)
      |> Asset.changeset(%{status: status})
      |> Repo.update()
      |> Sprout.Events.saved(:asset)
end
