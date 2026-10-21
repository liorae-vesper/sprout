defmodule Sprout.IntegrationsTest do
  use Sprout.DataCase
  alias Sprout.{Demo, Integrations, Land, Monitoring, Repo}

  setup do
    Demo.seed!()
    [field | _] = Land.list_fields()
    %{field: field}
  end

  test "keys are stored as digests, scoped to fields, and immediately revocable", %{field: field} do
    {:ok, client, secret} =
      Integrations.create_client(%{
        name: "Weather bridge",
        scopes: ["fields:read"],
        field_ids: [field.id]
      })

    assert String.starts_with?(secret, "sprout_")
    refute client.token_digest == secret
    assert client.token_digest == :crypto.hash(:sha256, secret)
    assert {:ok, authenticated} = Integrations.authenticate(secret)
    assert authenticated.id == client.id
    assert Enum.map(Integrations.permitted_fields(authenticated), & &1.id) == [field.id]
    assert {:ok, _} = Integrations.revoke_client(client.id)
    assert {:error, :unauthorized} = Integrations.authenticate(secret)
    assert {:error, :unauthorized} = Integrations.authenticate("invalid")
  end

  test "invalid scopes, missing fields and unknown field IDs cannot mint keys", %{field: field} do
    for attrs <- [
          %{name: "Bad scope", scopes: ["admin"], field_ids: [field.id]},
          %{name: "No field", scopes: ["fields:read"], field_ids: []},
          %{name: "Unknown field", scopes: ["fields:read"], field_ids: [9_999_999]}
        ] do
      assert {:error, %Ecto.Changeset{}} = Integrations.create_client(attrs)
    end

    assert Integrations.list_clients() == []
  end

  test "expired credentials are rejected", %{field: field} do
    {:ok, client, secret} =
      Integrations.create_client(%{
        name: "Expired",
        scopes: ["fields:read"],
        field_ids: [field.id]
      })

    client
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(DateTime.utc_now(), -60) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:error, :unauthorized} = Integrations.authenticate(secret)
  end

  test "retries return the original reading and changed payloads conflict", %{field: field} do
    {:ok, client, _} =
      Integrations.create_client(%{
        name: "Weather bridge",
        scopes: ["readings:write"],
        field_ids: [field.id]
      })

    attrs = %{"moisture" => 44, "temperature" => 25, "humidity" => 60, "water_l" => 2}
    Monitoring.subscribe()
    assert {:ok, reading, :created} = Integrations.ingest(client, field.id, attrs, "sample-0001")
    assert_receive {:farm_changed, :reading}
    assert {:ok, retried, :replayed} = Integrations.ingest(client, field.id, attrs, "sample-0001")
    assert retried.id == reading.id
    assert retried.source == :device
    refute_receive {:farm_changed, :reading}

    assert {:error, :conflict} =
             Integrations.ingest(client, field.id, Map.put(attrs, "moisture", 45), "sample-0001")
  end

  test "a rolled-back reading does not publish an invalidation", %{field: field} do
    Monitoring.subscribe()
    previous = Monitoring.latest(field.id)

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               Monitoring.record_reading(field, %{
                 moisture: 40,
                 temperature: 24,
                 humidity: 60,
                 water_l: 1
               })

               Repo.rollback(:cancelled)
             end)

    assert Monitoring.latest(field.id).id == previous.id
    refute_receive {:farm_changed, :reading}
  end

  test "a rejected sample does not reserve its retry key, and integrations have independent keys",
       %{field: field} do
    attrs = %{name: "Retry validation", scopes: ["readings:write"], field_ids: [field.id]}
    {:ok, first, _} = Integrations.create_client(attrs)
    {:ok, second, _} = Integrations.create_client(attrs)
    sample = %{"moisture" => 40, "temperature" => 25, "humidity" => 60, "water_l" => 1}

    assert {:error, %Ecto.Changeset{}} =
             Integrations.ingest(first, field.id, Map.put(sample, "moisture", 300), "retry-0001")

    assert {:ok, a, :created} = Integrations.ingest(first, field.id, sample, "retry-0001")
    assert {:ok, b, :created} = Integrations.ingest(second, field.id, sample, "retry-0001")
    assert a.id != b.id

    assert {:ok, replay, :replayed} =
             Integrations.ingest(first, field.id, Map.put(sample, "moisture", 40.0), "retry-0001")

    assert replay.id == a.id
  end

  test "malformed identifiers, keys, and sample shapes fail without database errors", %{
    field: field
  } do
    {:ok, client, _} =
      Integrations.create_client(%{
        name: "Bad input",
        scopes: ["readings:read", "readings:write"],
        field_ids: [field.id]
      })

    for id <- [nil, "nope", "99999999999999999999999", -1] do
      assert {:error, :not_found} = Integrations.authorized_field(client, id, "readings:read")
    end

    assert {:error, :invalid_idempotency_key} = Integrations.ingest(client, field.id, %{}, nil)

    assert {:error, :invalid_idempotency_key} =
             Integrations.ingest(client, field.id, %{}, "contains spaces")

    for sample <- [
          nil,
          [],
          %{},
          %{"moisture" => "40", "temperature" => 25, "humidity" => 60, "water_l" => 1}
        ] do
      assert {:error, :invalid_sample} =
               Integrations.ingest(client, field.id, sample, "sample-0001")
    end

    assert {:error, :unauthorized} = Integrations.authenticate(nil)
    assert {:error, :unauthorized} = Integrations.authenticate(String.duplicate("x", 129))
    assert {:error, :not_found} = Integrations.revoke_client(9_999_999)
  end
end
