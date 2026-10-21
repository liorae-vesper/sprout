defmodule Sprout.Land.CyclesTest do
  use Sprout.DataCase
  alias Sprout.{Cultivation, Land}

  defp plot do
    {:ok, plot} =
      Land.create_field(%{
        name: "Mint",
        area_ha: 1,
        boundary: %{"points" => [[0, 0], [0, 1], [1, 1], [1, 0]]}
      })

    plot
  end

  defp crop,
    do: %{name: "Mint", variety: "Green", baseline_kg_ha: 1000, planned_on: Date.utc_today()}

  test "preparation and rest are independent from planning; planting requires ready soil" do
    plot = plot()
    {:ok, cycle} = Cultivation.plan_crop(plot, crop())
    assert {:error, :plot_not_ready} = Cultivation.transition(cycle, :growing)
    assert {:error, :invalid_transition} = Cultivation.transition_plot(plot, :ready)
    {:ok, plot} = Cultivation.transition_plot(plot, :preparing)
    {:ok, plot} = Cultivation.transition_plot(plot, :ready)
    {:ok, growing} = Cultivation.transition(cycle, :growing)
    assert growing.planted_on == Date.utc_today()
    assert {:error, :plot_occupied} = Cultivation.transition_plot(plot, :resting)
    {:ok, harvested} = Cultivation.transition(growing, :harvested)
    assert harvested.harvested_on == Date.utc_today()
    assert Land.get_plot!(plot.id).soil_status == :resting
    assert Enum.map(Cultivation.history(plot.id), & &1.id) == [cycle.id]
  end

  test "next crop can be planned while growing, cancelled, and replanned without planting" do
    plot = plot()
    {:ok, plot} = Cultivation.transition_plot(plot, :preparing)
    {:ok, _} = Cultivation.transition_plot(plot, :ready)
    {:ok, current} = Cultivation.plan_crop(plot, crop())
    {:ok, current} = Cultivation.transition(current, :growing)
    {:ok, next} = Cultivation.plan_crop(plot, crop())
    assert Cultivation.active(plot.id).id == current.id
    assert Cultivation.next_cycle(plot.id).id == next.id
    assert {:error, _} = Cultivation.plan_crop(plot, crop())
    assert {:error, :plot_occupied} = Cultivation.transition(next, :growing)
    assert {:error, :invalid_transition} = Cultivation.transition(current, :cancelled)
    assert {:ok, %{status: :cancelled}} = Cultivation.transition(next, :cancelled)
    assert {:error, _} = Cultivation.transition(next, :growing)
    assert {:ok, _} = Cultivation.plan_crop(plot, crop())
  end

  test "ownership, soil status and actual dates cannot be injected through editable attributes" do
    plot = plot()

    {:ok, cycle} =
      Cultivation.plan_crop(
        plot,
        Map.merge(crop(), %{
          field_id: -1,
          status: :growing,
          planted_on: ~D[2000-01-01],
          harvested_on: ~D[2000-01-02]
        })
      )

    assert cycle.field_id == plot.id
    assert cycle.status == :planned
    assert cycle.planted_on == nil
    assert cycle.harvested_on == nil
    {:ok, preparing} = Cultivation.transition_plot(plot, :preparing)
    assert {:error, :stale_plot} = Cultivation.transition_plot(plot, :preparing)
    assert {:ok, %{soil_status: :resting}} = Cultivation.transition_plot(preparing, :resting)
  end
end
