# Developer garden · private beta

Open `/developers` from the farm's Developer garden link. The portal is a trusted
operator console for this single-farm demo, not a public signup or OAuth service.
It is enabled in development/test and disabled elsewhere unless explicitly configured:

```elixir
config :sprout, :developer_portal_enabled, true
```

The development server remains bound to loopback. Anyone admitted to the enabled
console can create and revoke credentials; there is no individual operator login.
Keep it behind your private access boundary. Public self-service access requires
operator identity, farm membership/tenancy, authorization, and deployment hardening.
The environment gate is checked for HTTP access, LiveView mount, and events.
Disabling the console does not revoke already-issued API keys.

## Connect a tool

1. Give the integration a name and select the exact fields it may access.
2. Grant only the required scopes. The default is field metadata access only.
3. Copy the bearer key immediately. Dismiss it after saving it in your secret store.
4. Set `SPROUT_API_KEY` in your shell and call the API. Use HTTPS outside loopback.

Keys contain 256 bits of cryptographic randomness. Only a SHA-256 digest and a
non-secret display prefix are persisted. Raw secrets are available only in the
issuance response/current LiveView socket; reloading cannot recover a key. They
expire after 90 days. Revocation rejects subsequent requests immediately; it does
not cancel already-running requests. Rotate by issuing a replacement, updating the
client, and revoking the old key. Portal and authenticated API responses use
`Cache-Control: no-store`. Provisioning never accepts caller-supplied token digests.

| Scope | Grants |
| --- | --- |
| `fields:read` | List permitted fields and their GPS boundaries |
| `readings:read` | Read up to 24 recent readings for a permitted field |
| `readings:write` | Submit device samples for a permitted field |

Every endpoint requires `Authorization: Bearer $SPROUT_API_KEY`. Keys in query
parameters/cookies are not accepted. Field grants apply independently of scopes;
requesting an ungranted or nonexistent field returns the same 404 response.

## First requests

```sh
curl --fail-with-body http://localhost:4010/api/v1/fields \
  -H "Authorization: Bearer $SPROUT_API_KEY"
```

Set `FIELD_ID` to a returned/granted field ID. Sending requires `readings:write`:

```sh
curl --fail-with-body -X POST \
  "http://localhost:4010/api/v1/fields/$FIELD_ID/readings" \
  -H "Authorization: Bearer $SPROUT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: leaf-sample-0001" \
  -d '{"moisture":44,"temperature":25,"humidity":68,"water_l":2}'
```

The request body must contain exactly those four JSON numbers. Units and ranges
are shared with the [device adapter contract](devices.md). The server sets the
field, `source: "device"`, and the ingestion timestamp; clients cannot override
those. Missing/extra properties, numeric strings, and out-of-range measurements
are rejected. Successful writes use `Monitoring.ingest_sample/3` and update the
live dashboard after commit. To accept only real data, disable the development
simulator with `config :sprout, :sensor_feed, nil`; otherwise simulated and
device samples intentionally share the same history.

```sh
curl --fail-with-body \
  "http://localhost:4010/api/v1/fields/$FIELD_ID/readings" \
  -H "Authorization: Bearer $SPROUT_API_KEY"
```

History contains at most 24 samples, oldest first, with `meta.limit` and
`meta.order`. It is not a complete-history export or paginated query.

## Retry contract

Each write requires an `Idempotency-Key`: 8–128 ASCII letters, digits, dots,
colons, underscores, or hyphens. Generate a new key for each distinct sample.
Reuse it only when retrying the same payload and field with the same integration.
A new sample returns 201; an identical replay returns 200 with the original
reading ID. The `Idempotency-Replayed` response header is `false` or `true`.
Reusing a key with different data/field returns 409. Numeric integer/float
representations normalize to the same stored request identity.

The retry record and reading commit together under a PostgreSQL transaction;
a per-client/key advisory lock serializes competing retries, backed by a unique
index. Replays do not insert rows or rebroadcast events. Failed validation rolls
back without reserving the key. Retry records currently have no expiry: do not
recycle old keys. A production retention and partitioning policy remains future work.

## Responses and contract

| Status | Meaning |
| --- | --- |
| 200 | Successful read or identical write replay |
| 201 | New sample committed |
| 400 | Missing/invalid idempotency key, or malformed JSON |
| 401 | Missing, invalid, expired, or revoked credential |
| 403 | Required scope absent |
| 404 | Field unknown or not granted |
| 409 | Idempotency key reused with changed data |
| 422 | Invalid sample or values |

API errors use an `errors` object with `detail`, plus `code` for domain errors
and optional `fields` for range validation. Framework-level malformed-JSON errors
can omit `code`. Do not retry authorization or validation errors unchanged.

The machine-readable contract is served at `/api/openapi.json`; its source is
`priv/openapi.json`. It uses [OpenAPI 3.1](https://spec.openapis.org/oas/v3.1.0.html).
Download it for tooling/client generation. No source-code-generated client SDK,
webhooks, rate limiting, public developer accounts, OAuth, or image upload API is
included in this private beta.

## Transaction notifications

`Events.saved/2` suppresses notifications inside an explicit repository
transaction. Transaction owners must publish successful results after commit;
rollback must stay silent. Integration writes implement this rule. Setup seeding
is deliberately silent. PubSub remains ephemeral; this is not a transactional
outbox or a durable webhook-delivery system.

## Parcels and plots

The v1 API keeps its `/fields` routes, field-scoped permissions, and existing IDs.
A v1 field is now explicitly a **growing plot**, contained by one land parcel.
Its sensor, scouting, equipment and image associations keep their IDs. Granting
access to a plot does not grant access to its parcel or sibling plots. Parcel
registration and cultivation commands remain operator workflows in this version.
