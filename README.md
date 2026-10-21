# Sprout 🌱

A small, working farm-management demo built with Elixir, Phoenix LiveView, Ecto, and PostgreSQL. Pastel fields, a smiling sun, and domain rules that live on the server.

## Run

Requires Elixir 1.20.4, Erlang/OTP 29.1.2, PostgreSQL 17, and Node.js 22+ with npm. Runtime versions are pinned in `mise.toml`; run `mise install` and activate mise (or prefix Mix commands with `mise exec --`).

Use the included database on a dedicated port:

```bash
docker compose up -d --wait
PGPORT=55433 mix setup
PGPORT=55433 mix phx.server
```

Open **http://localhost:4010**. Override the HTTP port with `PORT`.

For an existing PostgreSQL server, set `PGHOST`, `PGPORT`, `PGUSER`, and `PGPASSWORD` as needed. Development defaults are localhost:55432, postgres/postgres, database `sprout_dev`; tests use `sprout_test`. `mix setup` fetches dependencies, creates/migrates the database, seeds four parcels with growing plots, and builds assets. Seeding is repeatable and will not replace an existing farm. The included Compose database uses 55433 to avoid an existing workspace database on 55432.

```bash
mix precommit       # compile, formatting, strict Credo, coverage ≥80%, CRAP ≤30
mix docs            # ExDoc API reference in doc/
mix assets.build
```

Use `PGPORT=55433` for tests if using the included Compose service. On Linux, `inotify-tools` enables automatic browser reload after source edits; without it the application still runs, but reload the browser manually after edits.

## Try it

- Select a field to inspect its live soil moisture, Celsius temperature, humidity, and interval water consumption.
- Record a pest, disease, or nutrition finding with severity and GPS coordinates. Points outside the field are rejected; boundary edges are included. Resolve controlled findings to remove their pressure from the estimate while retaining the evidence.
- Watch another browser session update through PubSub after a saved change. The configurable supervised polling worker appends readings even with no browser open; development selects the simulated device adapter.
- Register the farm’s available land parcels, then draw growing plots inside them. Parcels and plots may share borders, but their interiors cannot overlap.
- Plan the next crop while the current cycle grows. Prepare resting soil and mark it ready before planting. Harvest returns soil to rest; cancelled and harvested cycles stay in history.
- Register field equipment and switch its readiness/maintenance status.
- Upload a JPEG or PNG original in the plant journal. Files stay private on disk, with field association and SHA-256 metadata in PostgreSQL. They remain `awaiting_model`; no disease inference is fabricated.

## Domain design

| Context | Owns | Rules |
| --- | --- | --- |
| `Sprout.Land` | Parcels and growing plots | Plots wholly inside a parcel, no overlapping interiors, shared borders allowed, valid GPS polygons |
| `Sprout.Cultivation` | Soil preparation, crop cycles, yield policy | Resting → preparing → ready; planting requires ready unoccupied soil; one growing and one planned next cycle per plot; planned cycles may be cancelled |
| `Sprout.Monitoring` | Append-only readings | Moisture/humidity 0–100%, temperature −50–70°C, nonnegative liters; latest reading has deterministic ordering |
| `Sprout.Health` | Geolocated scouting findings | Validated severity, location inside field, evidence retained after resolution |
| `Sprout.Equipment` | Field-assigned assets | Explicit kinds and availability states |
| `Sprout.Imaging` | Original intake, inference lifecycle | 8 MB limit, JPEG/PNG signature check, generated storage keys, checksum, conditional state transitions |

Contexts are the command boundary. LiveView orchestrates context calls and renders read models; it does not write schemas directly. Ecto changesets validate user input, PostgreSQL adds foreign keys/checks/uniqueness, and successful commands publish invalidation messages through Phoenix PubSub. The initial seed is wrapped in a transaction with an advisory lock. PubSub is ephemeral, not an audit/event log; notifications are suppressed inside explicit transactions, whose owners must publish after commit. Setup seeding is silent.

The small demo assembles its read model through context queries. Large installations should batch those reads and introduce telemetry retention/partitioning based on measured volume. Each application instance starts its configured polling worker in development; production leaves it disabled until an adapter is explicitly configured.

## Experimental yield policy

`Sprout.Cultivation.estimate/4` is a pure function:

```
kg = baseline_kg_per_ha × area_ha × moisture_factor × temperature_factor × health_factor
```

Moisture below 30% uses 0.65, above 80% uses 0.85, otherwise 1.0. Temperatures outside 10–32°C use 0.8. Open scouting severities sum into a pressure penalty capped at 80%. Resolved findings do not contribute. Missing readings return an insufficient-data result; readings older than 120 seconds are flagged stale. This is an explainable demonstration, not a calibrated agronomic forecast or statistical confidence interval. Humidity and water consumption are displayed but do not currently enter the estimate. No measured harvest weights are collected yet.

GPS geometry is planar and intended for local farm-scale polygons of 3–128 unique vertices (do not repeat the first vertex at the end). Area is entered explicitly, not derived geodesically. Global, polar, and antimeridian-spanning polygons require a geospatial implementation such as PostGIS. Polygon intersection uses triangulation and convex clipping, including concave parcels. An area tolerance of 1e-12 square degrees handles floating-point boundary contact; this is not survey-grade geometry.

## Land and cultivation model

A parcel is land available to the farm; it can contain zero or more plots and
uncultivated space. Parcels need not touch. Each plot belongs to exactly one
parcel. Soil status is independent of crop planning: a planned cycle neither
occupies land nor contributes to the dashboard yield estimate. Planting records
an actual date separately from the planned date, and harvest records its date
and returns soil to rest. History is retained rather than overwriting the crop.

Spatial creation commands serialize through a PostgreSQL transaction advisory
lock. Preparation and cycle transitions lock the persisted plot row, reject stale
commands, and commit their changes together. PostgreSQL also enforces foreign
keys and separate unique indexes for planned and growing cycles. Spatial checks
are enforced through context commands, not triggers; do not bypass contexts with
raw writes. The application remains a single farm.

The migration preserves plot IDs and attached readings, findings, images, assets,
and integration grants. Each legacy field becomes one parcel containing its
existing full-parcel plot. Invalid or overlapping legacy boundaries stop migration
for explicit correction. The old `fields` table, `field_id` foreign keys and v1
`/fields` endpoints remain stable storage/API names for plots; they do not grant
access to every plot in a parcel. `create_field/1` remains a legacy convenience
that atomically creates a parcel and its full-parcel plot; new UI workflows use
explicit `create_parcel/1` and `create_plot/2` commands.

The migration is forward-only because collapsing parcels and queued cycles would
lose domain information. Back up existing databases before upgrades; use a backup
restore for rollback. Legacy planting dates are retained as planned dates and,
for already planted cycles, also carried over as actual planting dates. Unknown
historic harvest dates remain unknown.

## Picture pipeline

`Imaging.ingest/3` preserves originals under `var/photos/` (ignored by Git). Metadata includes the original basename, a generated storage key, field ID, checksum, timestamps, status, and a future result map. The server never exposes originals as executable/static web content.

```
awaiting_model → processing → completed
                         ↘ failed → processing
```

`Imaging.transition/3` conditionally updates the persisted current state so two workers cannot both claim the same photo. Completion requires a nonempty result map; a future model should provide its version, labels, and scores. Upload checks identify file signatures, not a full image decode. A future inference worker must decode safely, bound pixel dimensions, handle malicious/corrupt content, and implement durable job scheduling/retries and recovery for interrupted processing. No worker or model is installed in this version.

## Scope

This is a **local single-farm demo**, bound to loopback in development. Device feeds are simulated. There is no user login, tenancy, treatment scheduling, trained inference model, or calibrated forecasting. The private-beta partner API authenticates field-scoped bearer keys; its operator portal is gated by deployment configuration and trusts the local/private access boundary. Before public deployment, add operator identity and farm membership/tenancy, API rate limiting, durable photo-job execution, object storage, backups, and operations appropriate to the deployment. Do not treat generated production release configuration as deployment readiness.

Phoenix context guidance: https://hexdocs.pm/phoenix/contexts.html

See [the development guide](docs/development.md) for focused test commands, quality reports, runtime setup, and CI.

See [device integration](docs/devices.md) for the adapter behaviour, configuration, polling isolation, and push ingestion. Physical transports can replace the simulator without changing persistence or LiveView.

The [private-beta developer garden](docs/integrations.md) at `/developers` issues scoped credentials and documents the authenticated sensor API. Download its contract at `/api/openapi.json`.
