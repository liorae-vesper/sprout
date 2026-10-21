defmodule SproutWeb.DashboardTest do
  use SproutWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    Sprout.Demo.seed!()
    :ok
  end

  test "dashboard selects fields, records scouting evidence, resolves it, and updates equipment",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, ".farm-app", "Little things. Growing beautifully.")
    assert has_element?(view, ".farm-app", "Strawberry nook")

    view
    |> element("button[phx-click='select'][phx-value-id='#{hd(Sprout.Land.list_fields()).id}']")
    |> render_click()

    view
    |> form("#finding-form",
      finding: %{
        kind: "pest",
        severity: "0.2",
        notes: "Aphids on lower leaves",
        latitude: "-23.550",
        longitude: "-46.630"
      }
    )
    |> render_submit()

    assert has_element?(view, ".farm-app", "Aphids on lower leaves")
    view |> element("button[phx-click='resolve']") |> render_click()
    assert has_element?(view, ".farm-app", "resolved")
    view |> element("button[phx-click='tab'][phx-value-tab='equipment']") |> render_click()
    assert has_element?(view, ".farm-app", "Little tractor")
  end

  test "invalid scouting coordinates display feedback", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#finding-form",
      finding: %{
        kind: "pest",
        severity: "0.2",
        notes: "Outside patch",
        latitude: "0",
        longitude: "0"
      }
    )
    |> render_submit()

    assert has_element?(view, ".farm-app", "outside this field")
  end

  test "saved sensor data reaches an already connected dashboard", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    field = hd(Sprout.Land.list_fields())

    {:ok, _} =
      Sprout.Monitoring.record_reading(field, %{
        moisture: 12.3,
        temperature: 35.5,
        humidity: 62.1,
        water_l: 7.2
      })

    _ = render(view)
    assert has_element?(view, ".farm-app", "12.3")
    assert has_element?(view, ".farm-app", "35.5")
    assert has_element?(view, ".farm-app", "12.3% moisture")
    assert has_element?(view, ".farm-app", "Latest manual reading")
    view |> element("button[phx-click='tab'][phx-value-tab='equipment']") |> render_click()
    asset = hd(Sprout.Equipment.list_assets())
    view |> element("button[phx-click='asset'][phx-value-id='#{asset.id}']") |> render_click()
    assert hd(Sprout.Equipment.list_assets()).status == :maintenance
  end
end
