defmodule SproutWeb.ManagementTest do
  use SproutWeb.ConnCase
  import Phoenix.LiveViewTest

  test "create a geofenced field, plan its crop, plant it, and assign equipment", %{conn: conn} do
    Sprout.Demo.seed!()

    {:ok, parcel} =
      Sprout.Land.create_parcel(%{
        name: "Mint land",
        area_ha: 2,
        boundary: %{"points" => [[0, 0], [0, 2], [2, 2], [2, 0]]}
      })

    {:ok, view, _} = live(conn, "/")

    view
    |> form("#field-form",
      field: %{
        parcel_id: parcel.id,
        name: "Minty meadow",
        area_ha: "0.5",
        boundary: "[[0,0],[0,1],[1,1],[1,0]]"
      }
    )
    |> render_submit()

    assert has_element?(view, ".farm-app", "Minty meadow")

    view
    |> form("#crop-form",
      crop: %{
        name: "Mint",
        variety: "Spearmint",
        baseline_kg_ha: "8000",
        planned_on: "2026-10-19"
      }
    )
    |> render_submit()

    assert has_element?(view, ".farm-app", "Spearmint")
    view |> element("#plot-prepare") |> render_click()
    view |> element("#plot-ready") |> render_click()
    view |> element("#cycle-plant") |> render_click()
    assert Sprout.Cultivation.active(List.last(Sprout.Land.list_fields()).id).status == :growing
    view |> element("button[phx-click='tab'][phx-value-tab='equipment']") |> render_click()

    view
    |> form("#asset-form", asset: %{name: "Mint sprinkler", kind: "pump", status: "ready"})
    |> render_submit()

    assert has_element?(view, ".farm-app", "Mint sprinkler")
  end

  test "field intake rejects malformed polygon JSON without crashing", %{conn: conn} do
    Sprout.Demo.seed!()
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#field-form", field: %{name: "Broken", area_ha: "1", boundary: "oops"})
    |> render_submit()

    assert has_element?(view, ".farm-app", "valid JSON")
  end
end
