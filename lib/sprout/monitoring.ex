defmodule Sprout.Monitoring do
  @moduledoc "Append-only sensor history. Values are percentages, Celsius, and liters per reading interval."
  import Ecto.Query
  alias Sprout.{Monitoring.Reading, Monitoring.Sample, Repo}

  @doc """
  Reads through the supplied adapter and ingests a normalized sample.

  Transport errors become `{:error, {:adapter, reason}}`; non-contract replies
  return `:invalid_adapter_response`. Range errors return a changeset. Adapter
  exceptions propagate; use the supervised feed for timeout/crash isolation.
  """
  @spec poll_field(Sprout.Land.Plot.t(), module(), keyword()) ::
          {:ok, Reading.t()} | {:error, term()}
  def poll_field(field, adapter, opts \\ []) do
    case adapter.read(field, latest(field.id), opts) do
      {:ok, %Sample{} = sample} -> ingest_sample(field, sample, adapter.source())
      {:error, reason} -> {:error, {:adapter, reason}}
      _ -> {:error, :invalid_adapter_response}
    end
  end

  @doc """
  Ingests a normalized polled or pushed sample through the standard validation pipeline.

  Physical readings default to `:device`; only `:device` and `:simulated` are
  accepted here. Field ownership is set by the trusted caller, never a payload.
  Push handlers must authenticate and map device IDs to fields before calling.
  Timestamps currently reflect server ingestion time, not device capture time.
  """
  @spec ingest_sample(Sprout.Land.Plot.t(), Sample.t(), :device | :simulated) ::
          {:ok, Reading.t()} | {:error, :invalid_source | Ecto.Changeset.t()}
  def ingest_sample(field, sample, source \\ :device)

  def ingest_sample(field, %Sample{} = sample, source) when source in [:device, :simulated] do
    record_reading(field, sample |> Map.from_struct() |> Map.put(:source, source))
  end

  def ingest_sample(_field, _sample, _source), do: {:error, :invalid_source}

  @doc """
  Subscribes the calling process to `{:farm_changed, kind}` notifications for this demo farm.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Sprout.PubSub, "farm")

  @doc """
  Appends a validated reading and broadcasts `:reading` on success.

  Moisture and humidity are percentages, temperature is Celsius, and `water_l`
  is liters consumed during this reading interval. `source` is manual, simulated, or a physical device.
  The field argument controls ownership; invalid values return a changeset.
  """
  @spec record_reading(Sprout.Land.Plot.t(), map()) ::
          {:ok, Reading.t()} | {:error, Ecto.Changeset.t()}
  def record_reading(field, attrs),
    do:
      %Reading{field_id: field.id}
      |> Reading.changeset(Map.drop(attrs, [:field_id, "field_id"]))
      |> Repo.insert()
      |> Sprout.Events.saved(:reading)

  @doc """
  Returns the newest field reading, or `nil`. IDs break timestamp ties.
  """
  @spec latest(integer()) :: Reading.t() | nil
  def latest(field_id),
    do:
      Repo.one(
        from r in Reading,
          where: r.field_id == ^field_id,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: 1
      )

  @doc """
  Returns up to 24 recent field readings, ordered oldest to newest for plotting.
  """
  @spec history(integer()) :: [Reading.t()]
  def history(field_id),
    do:
      Repo.all(
        from r in Reading,
          where: r.field_id == ^field_id,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: 24
      )
      |> Enum.reverse()
end
