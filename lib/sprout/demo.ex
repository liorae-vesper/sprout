defmodule Sprout.Demo do
  @moduledoc "Explicit demo fixtures and simulated telemetry; never claims to be a device feed."
  alias Ecto.Adapters.SQL
  alias Sprout.{Cultivation, Equipment, Land, Monitoring, Repo}

  @doc """
  Populates an empty database with four demo fields, crops, assets, and readings.

  A transaction and advisory lock serialize setup. Existing farms remain intact.
  Returns `:ok`; fixture failures raise and roll back the transaction.
  Setup writes suppress live notifications inside their outer transaction.
  """
  @spec seed!() :: :ok
  def seed! do
    Repo.transaction(fn ->
      SQL.query!(Repo, "SELECT pg_advisory_xact_lock(7712026)", [])

      if Land.list_fields() == [] do
        Enum.with_index([
          {"Strawberry nook", "Strawberries", "Albion", 1.2, 12_000},
          {"Sunshine patch", "Sweet corn", "Golden Bantam", 2.4, 9000},
          {"The leafy corner", "Kale", "Lacinato", 0.8, 16_000},
          {"Tomato meadow", "Tomatoes", "Sungold", 1.6, 22_000}
        ])
        |> Enum.each(&seed_field/1)
      end
    end)

    :ok
  end

  defp seed_field({{name, crop, variety, area, baseline}, i}) do
    lat = -23.55 + i * 0.004

    {:ok, field} =
      Land.create_field(%{
        name: name,
        area_ha: area,
        boundary: %{
          "points" => [
            [lat - 0.001, -46.631],
            [lat - 0.001, -46.629],
            [lat + 0.001, -46.629],
            [lat + 0.001, -46.631]
          ]
        }
      })

    {:ok, field} = Cultivation.transition_plot(field, :preparing)
    {:ok, field} = Cultivation.transition_plot(field, :ready)

    {:ok, cycle} =
      Cultivation.plan_crop(field, %{
        name: crop,
        variety: variety,
        baseline_kg_ha: baseline,
        planned_on: Date.add(Date.utc_today(), -35 - i * 5)
      })

    {:ok, _} = Cultivation.transition(cycle, :growing)

    {:ok, _} =
      Monitoring.record_reading(field, %{
        moisture: 48 - i * 8,
        temperature: 24 + i,
        humidity: 68 - i * 4,
        water_l: 12 + i * 3,
        source: :simulated
      })

    {:ok, _} =
      Equipment.create_asset(field, %{
        name: Enum.at(["Little tractor", "Drip irrigation", "Soil scout", "Garden toolkit"], i),
        kind: Enum.at([:tractor, :pump, :sensor, :tool], i),
        status: :ready
      })
  end
end
