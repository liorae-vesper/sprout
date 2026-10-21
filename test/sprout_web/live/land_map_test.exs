defmodule SproutWeb.LandMapTest do
  use SproutWeb.ConnCase
  import Phoenix.LiveViewTest

  test "map exposes saved polygons and accepts a drawn parcel", %{conn: conn} do
    Sprout.Demo.seed!()

    {:ok, parcel} =
      Sprout.Land.create_parcel(%{
        name: "New land",
        area_ha: 2,
        boundary: %{"points" => [[-24, -47], [-24, -46.635], [-23, -46.635], [-23, -47]]}
      })

    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#land-map[phx-hook='LandMap'][data-fields]")

    view
    |> form("#field-form",
      field: %{
        parcel_id: parcel.id,
        name: "Lavender bend",
        area_ha: "0.7",
        boundary: "[[-23.55,-46.64],[-23.55,-46.639],[-23.549,-46.64]]"
      }
    )
    |> render_submit()

    field = List.last(Sprout.Land.list_fields())
    assert field.name == "Lavender bend"
    assert Sprout.Land.contains?(field, -23.5499, -46.6399)
    assert has_element?(view, "#land-map[data-fields*='Lavender bend']")
  end

  test "crossed drawn boundaries are rejected without creating land", %{conn: conn} do
    Sprout.Demo.seed!()
    count = length(Sprout.Land.list_fields())
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#field-form",
      field: %{
        parcel_id: hd(Sprout.Land.list_parcels()).id,
        name: "Crossed",
        area_ha: "1",
        boundary: "[[0,0],[1,1],[0,1],[1,0]]"
      }
    )
    |> render_submit()

    assert length(Sprout.Land.list_fields()) == count
    assert has_element?(view, ".notice", "boundary")
  end
end
