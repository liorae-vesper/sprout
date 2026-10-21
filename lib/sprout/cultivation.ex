defmodule Sprout.Cultivation do
  @moduledoc "Crop-cycle aggregate and a pure, deliberately transparent experimental yield model."
  import Ecto.Query
  alias Ecto.Changeset
  alias Sprout.Cultivation.Crop
  alias Sprout.Land.Plot
  alias Sprout.Repo

  @doc """
  Lists every crop cycle, including harvested history, in creation order.
  """
  @spec list_crops() :: [Crop.t()]
  def list_crops, do: Repo.all(from c in Crop, order_by: c.id)

  @doc "Returns the growing cycle only; planned cycles do not occupy soil or contribute yield."
  @spec active(integer()) :: Crop.t() | nil
  def active(plot_id),
    do: Repo.one(from c in Crop, where: c.field_id == ^plot_id and c.status == :growing)

  @doc "Returns the single planned next cycle, independently of the current growing cycle."
  @spec next_cycle(integer()) :: Crop.t() | nil
  def next_cycle(plot_id),
    do: Repo.one(from c in Crop, where: c.field_id == ^plot_id and c.status == :planned)

  @doc "Lists all cycles for a plot, newest first, including cancelled and harvested history."
  @spec history(integer()) :: [Crop.t()]
  def history(plot_id),
    do: Repo.all(from c in Crop, where: c.field_id == ^plot_id, order_by: [desc: c.id])

  @doc "Plans the next cycle. Ownership, state, and actual planting/harvest dates are context-owned."
  @spec plan_crop(Plot.t(), map()) :: {:ok, Crop.t()} | {:error, Changeset.t()}
  def plan_crop(%Plot{} = plot, attrs) do
    %Crop{field_id: plot.id}
    |> Crop.changeset(attrs)
    |> Repo.insert()
    |> Sprout.Events.saved(:crop)
  end

  @doc "Advances planned → growing → harvested, or cancels a planned cycle. Planting requires ready, unoccupied soil."
  @spec transition(Crop.t(), atom()) :: {:ok, Crop.t()} | {:error, atom() | Changeset.t()}
  def transition(%Crop{} = crop, target) do
    command(fn ->
      plot = lock_plot(crop.field_id)
      current = Repo.get!(Crop, crop.id)
      if current.lock_version != crop.lock_version, do: Repo.rollback(:stale_cycle)
      advance(current, target, plot)
    end)
  end

  @doc "Moves resting → preparing → ready, or returns unoccupied soil to rest. Stale plot commands are rejected."
  @spec transition_plot(Plot.t(), atom()) :: {:ok, Plot.t()} | {:error, atom() | Changeset.t()}
  def transition_plot(%Plot{} = plot, target) do
    command(fn ->
      current = lock_plot(plot.id)
      if current.lock_version != plot.lock_version, do: Repo.rollback(:stale_plot)
      if active(plot.id), do: Repo.rollback(:plot_occupied)

      unless {current.soil_status, target} in [
               {:resting, :preparing},
               {:preparing, :ready},
               {:preparing, :resting},
               {:ready, :resting}
             ],
             do: Repo.rollback(:invalid_transition)

      save_plot(current, target)
    end)
  end

  defp command(fun), do: Repo.transaction(fun) |> Sprout.Events.saved(:crop)
  defp lock_plot(id), do: Repo.one!(from p in Plot, where: p.id == ^id, lock: "FOR UPDATE")

  defp advance(%{status: :planned} = crop, :growing, plot) do
    if active(plot.id), do: Repo.rollback(:plot_occupied)
    if plot.soil_status != :ready, do: Repo.rollback(:plot_not_ready)
    save_crop(crop, status: :growing, planted_on: Date.utc_today())
  end

  defp advance(%{status: :growing} = crop, :harvested, plot) do
    save_plot(plot, :resting)
    save_crop(crop, status: :harvested, harvested_on: Date.utc_today())
  end

  defp advance(%{status: :planned} = crop, :cancelled, _), do: save_crop(crop, status: :cancelled)
  defp advance(_, _, _), do: Repo.rollback(:invalid_transition)

  defp save_crop(crop, attrs),
    do: crop |> Changeset.change(attrs) |> Changeset.optimistic_lock(:lock_version) |> update()

  defp save_plot(plot, status),
    do:
      plot
      |> Changeset.change(soil_status: status)
      |> Changeset.optimistic_lock(:lock_version)
      |> update()

  defp update(changeset) do
    case Repo.update(changeset, stale_error_field: :status) do
      {:ok, record} -> record
      {:error, error} -> Repo.rollback(error)
    end
  end

  @doc """
  Calculates an experimental yield in kilograms from baseline, hectares, and field stress.

  Moisture below 30% multiplies yield by 0.65; above 80% uses 0.85.
  Temperatures outside 10–32°C use 0.8. Open finding severities reduce yield,
  with combined pressure capped at 80%. Humidity and water liters are not inputs.

  Missing readings produce `kg: nil`; readings older than 120 seconds are stale.
  Absent `inserted_at` timestamps are treated as fresh for pure calculations.
  This heuristic is not a calibrated forecast or a statistical confidence interval.

  ## Examples

      iex> estimate = Sprout.Cultivation.estimate(%{baseline_kg_ha: 1000}, 2, %{moisture: 50, temperature: 24}, [])
      iex> estimate.kg
      2000.0
  """
  @spec estimate(map(), number(), map() | nil, [map()]) :: %{
          kg: float() | nil,
          confidence: atom(),
          factors: keyword(),
          stale: boolean()
        }
  def estimate(_, _, nil, _), do: %{kg: nil, confidence: :insufficient, factors: [], stale: true}

  def estimate(crop, area, reading, findings) do
    water =
      cond do
        reading.moisture < 30 -> 0.65
        reading.moisture > 80 -> 0.85
        true -> 1.0
      end

    heat = if reading.temperature > 32 or reading.temperature < 10, do: 0.8, else: 1.0

    pressure =
      findings
      |> Enum.filter(&(&1.status == :open))
      |> Enum.map(& &1.severity)
      |> Enum.sum()
      |> min(0.8)

    stale =
      case Map.get(reading, :inserted_at) do
        nil -> false
        date -> DateTime.diff(DateTime.utc_now(), date) > 120
      end

    %{
      kg: Float.round(crop.baseline_kg_ha * area * water * heat * (1 - pressure), 1),
      confidence: if(stale, do: :stale, else: :experimental),
      stale: stale,
      factors: [water: water, temperature: heat, field_health: 1 - pressure]
    }
  end
end
