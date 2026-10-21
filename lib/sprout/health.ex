defmodule Sprout.Health do
  @moduledoc "Geofenced scouting findings. Resolution records control of pressure without deleting evidence."
  import Ecto.Query
  alias Sprout.{Health.Finding, Land, Repo}

  @doc """
  Lists a field’s scouting evidence newest first, including resolved findings.
  """
  @spec list_findings(integer()) :: [Finding.t()]
  def list_findings(field_id),
    do: Repo.all(from f in Finding, where: f.field_id == ^field_id, order_by: [desc: f.id])

  @doc """
  Records a pest, disease, or nutrition finding inside the field boundary.

  Severity is a fraction from 0 to 1. Invalid attributes return a changeset;
  valid coordinates outside the polygon return `{:error, :outside_field}`.
  Ownership and initial `:open` status come from the context.
  """
  @spec record_finding(Sprout.Land.Plot.t(), map()) ::
          {:ok, Finding.t()} | {:error, :outside_field | Ecto.Changeset.t()}
  def record_finding(field, attrs) do
    changeset =
      Finding.changeset(
        %Finding{field_id: field.id},
        Map.drop(attrs, [:field_id, "field_id", :status, "status"])
      )

    cond do
      not changeset.valid? ->
        {:error, changeset}

      not Land.contains?(
        field,
        Ecto.Changeset.get_field(changeset, :latitude),
        Ecto.Changeset.get_field(changeset, :longitude)
      ) ->
        {:error, :outside_field}

      true ->
        changeset |> Repo.insert() |> Sprout.Events.saved(:finding)
    end
  end

  @doc """
  Marks a finding resolved without removing its evidence; repeated resolution is safe.

  Broadcasts on success. Raises `Ecto.NoResultsError` if the ID does not exist.
  """
  @spec resolve(integer() | String.t()) :: {:ok, Finding.t()} | {:error, Ecto.Changeset.t()}
  def resolve(id),
    do:
      Repo.get!(Finding, id)
      |> Ecto.Changeset.change(status: :resolved)
      |> Repo.update()
      |> Sprout.Events.saved(:finding)
end
