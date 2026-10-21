defmodule SproutWeb.DeviceReadingTest do
  use SproutWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Sprout.{Demo, Land, Monitoring}
  alias Sprout.Monitoring.Sample

  test "a pushed physical sample updates the connected view with the correct source", %{
    conn: conn
  } do
    Demo.seed!()
    {:ok, view, _} = live(conn, "/")
    field = hd(Land.list_fields())
    sample = %Sample{moisture: 42.8, temperature: 26.2, humidity: 72.1, water_l: 3.4}
    assert {:ok, _} = Monitoring.ingest_sample(field, sample)
    assert has_element?(view, ".live-dot", "Latest device reading")
    assert has_element?(view, "#field-cards", "42.8% moisture")
  end
end
