defmodule SproutWeb.DeveloperPortalTest do
  use SproutWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Sprout.{Demo, Integrations, Land}

  setup do
    Demo.seed!()
    :ok
  end

  test "portal issues a scoped key once, hides it on dismissal and revokes access", %{conn: conn} do
    [field | _] = Land.list_fields()
    {:ok, view, _} = live(conn, "/developers")
    assert has_element?(view, "h1", "Plant an integration")

    view
    |> form("#integration-form",
      client: %{
        name: "Partner weather station",
        field_ids: [field.id],
        scopes: ["fields:read", "readings:write"]
      }
    )
    |> render_submit()

    assert has_element?(view, "#new-api-key")
    [client] = Integrations.list_clients()
    assert has_element?(view, "#integration-clients", "Partner weather station")
    view |> element("#dismiss-key") |> render_click()
    refute has_element?(view, "#new-api-key")
    view |> element("#revoke-client-#{client.id}") |> render_click()
    assert has_element?(view, "#integration-clients", "Revoked")
    refute has_element?(view, "#revoke-client-#{client.id}")
  end

  test "invalid provisioning shows feedback", %{conn: conn} do
    {:ok, view, _} = live(conn, "/developers")

    view
    |> form("#integration-form", client: %{name: "x", field_ids: [], scopes: []})
    |> render_submit()

    assert has_element?(view, "#portal-notice", "Could not issue")
    assert Integrations.list_clients() == []
  end

  test "the private operator portal can be disabled", %{conn: conn} do
    previous = Application.get_env(:sprout, :developer_portal_enabled)
    Application.put_env(:sprout, :developer_portal_enabled, false)
    on_exit(fn -> Application.put_env(:sprout, :developer_portal_enabled, previous) end)
    assert conn |> get("/developers") |> response(404)
  end

  test "an already connected portal cannot issue keys after the gate is disabled", %{conn: conn} do
    {:ok, view, _} = live(conn, "/developers")
    previous = Application.get_env(:sprout, :developer_portal_enabled)
    Application.put_env(:sprout, :developer_portal_enabled, false)
    on_exit(fn -> Application.put_env(:sprout, :developer_portal_enabled, previous) end)
    field = hd(Land.list_fields())

    view
    |> form("#integration-form",
      client: %{name: "Blocked", field_ids: [field.id], scopes: ["fields:read"]}
    )
    |> render_submit()

    assert_redirect(view, "/")
    assert Integrations.list_clients() == []
  end
end
