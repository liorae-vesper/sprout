defmodule SproutWeb.PhotoTest do
  use SproutWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Sprout.{Demo, Imaging, Land}

  setup do
    Demo.seed!()
    :ok
  end

  test "an uploaded original is preserved with metadata and shown after navigating back", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    view |> element("button[phx-value-tab='photos']") |> render_click()

    bytes =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4mQAAAAASUVORK5CYII="
      )

    upload =
      file_input(view, "#photo-form", :leaf, [
        %{name: "healthy-leaf.png", content: bytes, type: "image/png"}
      ])

    render_upload(upload, "healthy-leaf.png")
    view |> form("#photo-form") |> render_submit()
    assert has_element?(view, ".notice", "Photo preserved")
    [photo] = Imaging.list_photos(hd(Land.list_fields()).id)
    assert File.read!(Imaging.path(photo)) == bytes
    assert photo.status == :awaiting_model
    view |> element("button[phx-value-tab='overview']") |> render_click()
    view |> element("button[phx-value-tab='photos']") |> render_click()
    assert has_element?(view, "#photo-list", "healthy-leaf.png")
  end

  test "a disguised image is rejected without adding metadata", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    view |> element("button[phx-value-tab='photos']") |> render_click()

    upload =
      file_input(view, "#photo-form", :leaf, [
        %{name: "bad.png", content: "not an image", type: "image/png"}
      ])

    render_upload(upload, "bad.png")
    view |> form("#photo-form") |> render_submit()
    assert has_element?(view, ".notice", "valid PNG or JPEG")
    assert Imaging.list_photos(hd(Land.list_fields()).id) == []
  end

  test "invalid field values show actionable validation feedback", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")

    view
    |> form("#field-form",
      field: %{
        parcel_id: hd(Land.list_parcels()).id,
        name: "Invalid area",
        area_ha: "-1",
        boundary: "[[0,0],[0,1],[1,0]]"
      }
    )
    |> render_submit()

    assert has_element?(view, ".notice", "area_ha")
    refute Enum.any?(Land.list_fields(), &(&1.name == "Invalid area"))
  end
end
