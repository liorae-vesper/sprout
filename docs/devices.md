# Device integration

`Sprout.Monitoring.DeviceAdapter` is the polling contract. The fake adapter implements it just like a physical transport would:

```elixir
@behaviour Sprout.Monitoring.DeviceAdapter
```

Implement both callbacks:

- `source/0` returns `:device` for physical devices or `:simulated` for generated data.
- `read(field, previous_reading, adapter_options)` returns `{:ok, %Sprout.Monitoring.Sample{}}` or `{:error, reason}`. The previous reading can be `nil`.

Adapters fetch and decode data; they do not write to the repository or publish events. `Sprout.Monitoring.poll_field/3` joins the transport to the shared `ingest_sample/3` pipeline. Ingestion validates ranges, persists the reading, and broadcasts only successful writes. A malformed adapter result returns `:invalid_adapter_response`; a transport error becomes `{:adapter, reason}`. Exceptions propagate from direct polling calls; the supervised worker isolates them.

## Canonical sample

A sample contains all four measurements:

| Field | Unit | Accepted range |
| --- | --- | --- |
| `moisture` | percent | 0–100 |
| `temperature` | Celsius | −50–70 |
| `humidity` | percent | 0–100 |
| `water_l` | liters consumed during this sample interval | ≥0 |

Convert vendor units in the adapter. In particular, convert cumulative water-meter totals to interval consumption before ingestion. Missing, invalid, or unavailable readings must produce an error; do not substitute zeros or fake measurements. The field comes from trusted application configuration, not the device payload. Timestamps currently represent server ingestion time; device IDs and capture timestamps are not yet persisted.

## Selecting a polling implementation

Development uses this configuration in `config/dev.exs`:

```elixir
config :sprout, :sensor_feed,
  adapter: Sprout.Monitoring.SimulatedAdapter,
  adapter_options: [],
  interval: 5000,
  timeout: 2000,
  max_concurrency: 4
```

After implementing your physical adapter, set `:adapter` to its module and pass its configuration through `:adapter_options`. That keyword list can supply a client reference or field-ID-to-device mapping. Restart the application after configuration changes. No monitoring-domain or dashboard changes are needed.

The feed is disabled when `:sensor_feed` is absent or nil, including the default test and production configuration. Configure an adapter explicitly in the target environment to enable it. Remove the setting or set it to nil for push-only installations.

`Sprout.Monitoring.Feed` polls fields concurrently under `Sprout.Monitoring.Tasks`. Each task has a timeout and is terminated when exceeded. A device returning an error, crashing, or timing out does not prevent other fields from saving their samples. Failures are logged with the field ID and retried on the next interval; the worker never falls back to simulation. A completed batch schedules the next interval, so polling batches do not overlap. The interval is a delay after batch completion, not a strict sampling deadline. Real adapters should also set transport/client timeouts and release resources when their task terminates.

One feed runs per configured application node. A multi-node installation needs an ownership/scheduling policy to avoid duplicate polling. This version does not provide discovery, vendor drivers, hardware authentication, ingestion idempotency, or automatic retries of individual samples.

## Push transports

An authenticated MQTT subscriber or HTTP handler can normalize a payload and call:

```elixir
sample = %Sprout.Monitoring.Sample{
  moisture: 44.0,
  temperature: 25.0,
  humidity: 68.0,
  water_l: 0.0
}

Sprout.Monitoring.ingest_sample(field, sample)
```

The default source is `:device`. The same validation, persistence, and PubSub path is used for polled and pushed data. Authenticate the sender and resolve its authorized field before this call; this context function itself is not a network endpoint. The [private-beta integration API](integrations.md) exposes authenticated HTTP ingestion through the same boundary. Do not create atoms from untrusted device IDs or configuration strings.

## Tests

`test/support/devices/adapter.ex` implements the behaviour as a deterministic test transport. Contract tests prove that replacing the simulator still persists validated readings and emits live updates. Worker tests exercise scheduled polls, isolation, timeout/crash recovery, and invalid configuration. The connected-view test proves physical readings receive their own source label.

```sh
mise exec -- mix test test/sprout/device_adapter_test.exs test/sprout/device_feed_test.exs test/sprout_web/live/device_reading_test.exs
mise exec -- mix precommit
```
