defmodule SproutWeb.IntegrationAPITest do
  use SproutWeb.ConnCase
  alias Sprout.{Demo, Integrations, Land, Monitoring}

  setup do
    Demo.seed!()
    [field, other | _] = Land.list_fields()

    {:ok, client, token} =
      Integrations.create_client(%{
        name: "Partner",
        scopes: ["fields:read", "readings:read", "readings:write"],
        field_ids: [field.id]
      })

    %{field: field, other: other, client: client, token: token}
  end

  test "API requires bearer credentials and returns only permitted fields", %{
    conn: conn,
    field: field,
    token: token
  } do
    assert conn |> get("/api/v1/fields") |> json_response(401)
    body = conn |> authorized(token) |> get("/api/v1/fields") |> json_response(200)
    assert Enum.map(body["data"], & &1["id"]) == [field.id]
  end

  test "writes are scoped, validated, idempotent and appear in reading history", %{
    conn: conn,
    field: field,
    other: other,
    token: token
  } do
    attrs = %{"moisture" => 42.5, "temperature" => 25, "humidity" => 65, "water_l" => 2}
    path = "/api/v1/fields/#{field.id}/readings"
    result = conn |> request(token, "sensor-0001") |> post(path, attrs) |> json_response(201)
    repeated = conn |> request(token, "sensor-0001") |> post(path, attrs) |> json_response(200)
    assert result["data"]["id"] == repeated["data"]["id"]
    assert result["data"]["source"] == "device"

    assert conn
           |> request(token, "sensor-0001")
           |> post(path, Map.put(attrs, "moisture", 30))
           |> json_response(409)

    assert conn |> authorized(token) |> post(path, attrs) |> json_response(400)

    assert conn
           |> request(token, "sensor-0002")
           |> post(path, Map.put(attrs, "moisture", 300))
           |> json_response(422)

    assert conn
           |> request(token, "sensor-0003")
           |> post(path, Map.put(attrs, "source", "simulated"))
           |> json_response(422)

    assert conn
           |> request(token, "sensor-0004")
           |> post("/api/v1/fields/#{other.id}/readings", attrs)
           |> json_response(404)

    history = conn |> authorized(token) |> get(path) |> json_response(200)
    assert List.last(history["data"])["id"] == result["data"]["id"]
    assert Monitoring.latest(field.id).moisture == 42.5
  end

  test "read-only credentials cannot write and revoked credentials cannot read", %{
    conn: conn,
    field: field,
    client: client,
    token: token
  } do
    {:ok, _, read_token} =
      Integrations.create_client(%{
        name: "Read only",
        scopes: ["fields:read"],
        field_ids: [field.id]
      })

    assert conn
           |> request(read_token, "sensor-0001")
           |> post("/api/v1/fields/#{field.id}/readings", %{})
           |> json_response(403)

    Integrations.revoke_client(client.id)
    assert conn |> authorized(token) |> get("/api/v1/fields") |> json_response(401)

    assert conn
           |> authorized(read_token)
           |> get("/api/v1/fields/nope/readings")
           |> json_response(403)
  end

  test "the published contract describes the real API", %{conn: conn} do
    spec = conn |> get("/api/openapi.json") |> json_response(200)
    assert spec["openapi"] == "3.1.0"
    assert spec["paths"]["/api/v1/fields/{field_id}/readings"]["post"]["responses"]["409"]
    assert spec["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
  end

  defp authorized(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp request(conn, token, key),
    do: conn |> authorized(token) |> put_req_header("idempotency-key", key)
end
