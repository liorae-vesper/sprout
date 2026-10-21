defmodule SproutWeb.ParcelWorkflowTest do
  use SproutWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Sprout.{Cultivation, Land}

  test "register land, draw a plot, prepare it, and plant a planned cycle", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#parcel-form",
      parcel: %{name: "Home acre", area_ha: "2", boundary: "[[0,0],[0,2],[2,2],[2,0]]"}
    )
    |> render_submit()

    parcel = hd(Land.list_parcels())
    assert Land.list_plots() == []

    view
    |> form("#field-form",
      field: %{
        parcel_id: parcel.id,
        name: "Herb bed",
        area_ha: "0.3",
        boundary: "[[0,0],[0,1],[1,1],[1,0]]"
      }
    )
    |> render_submit()

    plot = hd(Land.list_plots())
    assert has_element?(view, "#land-map[data-parcels*='Home acre']")

    view
    |> form("#crop-form",
      crop: %{name: "Mint", variety: "Green", baseline_kg_ha: "1000", planned_on: "2026-11-01"}
    )
    |> render_submit()

    assert Cultivation.active(plot.id) == nil
    view |> element("#plot-prepare") |> render_click()
    view |> element("#plot-ready") |> render_click()
    view |> element("#cycle-plant") |> render_click()
    assert Cultivation.active(plot.id).name == "Mint"
    assert has_element?(view, "#crop-form")
    view |> element("button[phx-click='crop']") |> render_click()
    assert Land.get_plot!(plot.id).soil_status == :resting
    assert has_element?(view, "#cycle-history", "harvested")
  end

  test "unknown lifecycle targets cannot cancel the next crop", %{conn: conn} do
    Sprout.Demo.seed!()
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#crop-form",
      crop: %{
        name: "Next mint",
        variety: "Green",
        baseline_kg_ha: "1000",
        planned_on: "2026-11-01"
      }
    )
    |> render_submit()

    plot = hd(Land.list_plots())
    render_click(view, "cycle", %{"target" => "unexpected"})
    assert Cultivation.next_cycle(plot.id).name == "Next mint"
    view |> element("#cycle-cancel") |> render_click()
    assert Cultivation.next_cycle(plot.id) == nil
    assert Cultivation.active(plot.id).status == :growing
  end
end
