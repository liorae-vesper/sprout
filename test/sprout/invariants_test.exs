defmodule Sprout.InvariantsTest do
  use Sprout.DataCase
  alias Sprout.{Cultivation, Land, Monitoring}

  defp field do
    {:ok, field} =
      Land.create_field(%{
        name: "Patch",
        area_ha: 1,
        boundary: %{"points" => [[0, 0], [0, 1], [1, 1], [1, 0]]}
      })

    {:ok, field} = Cultivation.transition_plot(field, :preparing)
    {:ok, field} = Cultivation.transition_plot(field, :ready)
    field
  end

  test "valid polygons with separated collinear edges are accepted" do
    assert Land.valid_boundary?(%{
             "points" => [[0, 0], [0, 1], [1, 1], [1, 2], [0, 2], [0, 3], [2, 3], [2, 0]]
           })
  end

  test "self intersections, duplicates and invalid GPS coordinates are rejected" do
    refute Land.valid_boundary?(%{"points" => [[0, 0], [1, 1], [0, 1], [1, 0]]})
    refute Land.valid_boundary?(%{"points" => [[0, 0], [0, 1], [1, 1], [0, 0]]})
    refute Land.valid_boundary?(%{"points" => [[91, 0], [0, 1], [1, 1]]})
    refute Land.contains?(field(), nil, nil)
  end

  test "only one active cycle exists and stale lifecycle transitions are rejected" do
    field = field()

    attrs = %{
      name: "Mint",
      variety: "Spearmint",
      baseline_kg_ha: 8000,
      planned_on: Date.utc_today()
    }

    {:ok, planned} = Cultivation.plan_crop(field, attrs)
    assert {:error, _} = Cultivation.plan_crop(field, attrs)
    {:ok, growing} = Cultivation.transition(planned, :growing)
    assert {:error, _} = Cultivation.transition(planned, :growing)
    {:ok, _} = Cultivation.transition(growing, :harvested)
    assert {:ok, _} = Cultivation.plan_crop(field, attrs)
  end

  test "field ownership and crop state cannot be injected through intake" do
    first = field()

    {:ok, second} =
      Land.create_field(%{
        name: "Elsewhere",
        area_ha: 1,
        boundary: %{"points" => [[2, 2], [2, 3], [3, 3], [3, 2]]}
      })

    {:ok, crop} =
      Cultivation.plan_crop(first, %{
        field_id: second.id,
        status: :harvested,
        name: "Mint",
        variety: "Green",
        baseline_kg_ha: 8000,
        planned_on: Date.utc_today()
      })

    assert crop.field_id == first.id
    assert crop.status == :planned
  end

  test "stale readings remain visibly uncertain and rejected readings emit no events" do
    field = field()
    Monitoring.subscribe()

    assert {:error, _} =
             Monitoring.record_reading(field, %{
               moisture: 40,
               temperature: 200,
               humidity: 70,
               water_l: 1
             })

    refute_receive {:farm_changed, :reading}

    estimate =
      Cultivation.estimate(
        %{baseline_kg_ha: 1000},
        1,
        %{moisture: 50, temperature: 24, inserted_at: DateTime.add(DateTime.utc_now(), -180)},
        []
      )

    assert estimate.stale
    assert estimate.confidence == :stale
  end
end
