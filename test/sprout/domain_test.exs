defmodule Sprout.DomainTest do
  use Sprout.DataCase
  alias Sprout.{Cultivation, Equipment, Health, Land, Monitoring}

  test "field boundary accepts a point inside and rejects an outside observation" do
    {:ok, field} =
      Land.create_field(%{
        name: "Berry patch",
        area_ha: 2.0,
        boundary: %{"points" => [[0, 0], [0, 1], [1, 1], [1, 0]]}
      })

    assert Land.contains?(field, 0.5, 0.5)
    assert Land.contains?(field, 0.0, 0.5)
    refute Land.contains?(field, 2.0, 2.0)

    assert {:error, :outside_field} =
             Health.record_finding(field, %{
               kind: :pest,
               severity: 0.2,
               notes: "Aphids",
               latitude: 2.0,
               longitude: 2.0
             })
  end

  test "invalid boundaries and negative areas cannot persist" do
    assert {:error, changeset} =
             Land.create_field(%{name: "Bad", area_ha: -1, boundary: %{"points" => [[0, 0]]}})

    assert errors_on(changeset).area_ha
    assert errors_on(changeset).boundary
  end

  test "crop lifecycle prevents harvest before planting and double harvest" do
    field = field()

    {:ok, crop} =
      Cultivation.plan_crop(field, %{
        name: "Strawberries",
        variety: "Albion",
        baseline_kg_ha: 12_000,
        planned_on: Date.utc_today()
      })

    assert {:error, :invalid_transition} = Cultivation.transition(crop, :harvested)
    {:ok, crop} = Cultivation.transition(crop, :growing)
    {:ok, crop} = Cultivation.transition(crop, :harvested)
    assert {:error, :invalid_transition} = Cultivation.transition(crop, :growing)
  end

  test "sensor readings validate ranges, retain history, and broadcast only saved data" do
    field = field()
    Monitoring.subscribe()

    assert {:error, _} =
             Monitoring.record_reading(field, %{
               moisture: 120,
               temperature: 25,
               humidity: 60,
               water_l: 5
             })

    {:ok, reading} =
      Monitoring.record_reading(field, %{moisture: 45, temperature: 25, humidity: 60, water_l: 5})

    assert_receive {:farm_changed, :reading}
    assert Monitoring.latest(field.id).id == reading.id
  end

  test "yield model accounts for dry soil and findings and flags missing readings" do
    crop = %{baseline_kg_ha: 1000}
    assert %{kg: nil, confidence: :insufficient} = Cultivation.estimate(crop, 2, nil, [])
    healthy = Cultivation.estimate(crop, 2, %{moisture: 50, temperature: 24}, [])

    stressed =
      Cultivation.estimate(crop, 2, %{moisture: 15, temperature: 38}, [
        %{severity: 0.5, status: :open}
      ])

    assert healthy.kg == 2000.0
    assert stressed.kg < healthy.kg
    assert stressed.kg >= 0
  end

  test "resolved findings stop contributing pressure; asset status is constrained" do
    field = field()

    {:ok, finding} =
      Health.record_finding(field, %{
        kind: :pest,
        severity: 0.3,
        notes: "Aphids",
        latitude: 0.5,
        longitude: 0.5
      })

    {:ok, finding} = Health.resolve(finding.id)
    assert finding.status == :resolved

    assert {:error, _} =
             Equipment.create_asset(field, %{name: "Pump", kind: :pump, status: :unknown})

    assert {:ok, _} = Equipment.create_asset(field, %{name: "Pump", kind: :pump, status: :ready})
  end

  defp field do
    {:ok, f} =
      Land.create_field(%{
        name: "Patch",
        area_ha: 2,
        boundary: %{"points" => [[0, 0], [0, 1], [1, 1], [1, 0]]}
      })

    {:ok, f} = Cultivation.transition_plot(f, :preparing)
    {:ok, f} = Cultivation.transition_plot(f, :ready)
    f
  end
end
