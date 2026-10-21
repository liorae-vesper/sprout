# Development

Use the exact versions in `mise.toml`. Install Node.js 22 or newer with npm;
`mix assets.setup` installs the locked Leaflet browser dependency.

```sh
mise trust
mise install
mise exec -- elixir --version
docker compose up -d --wait
PGPORT=55433 mise exec -- mix setup
PGPORT=55433 mise exec -- mix phx.server
```

The web server uses port 4010. The Compose database uses port 55433. Export
`PGPORT=55433` in your shell when using Compose; an existing local database
on port 55432 remains supported. `PGHOST`, `PGUSER`, and `PGPASSWORD` override
connection defaults. Never use a production database for tests or reset commands.

Runtime pins were checked against the official [Elixir 1.20.4 release](https://github.com/elixir-lang/elixir/releases/tag/v1.20.4) and [Erlang/OTP 29.1.2 release](https://github.com/erlang/otp/releases/tag/OTP-29.1.2) on October 19, 2026. CI reads `mise.toml` directly so it uses the same versions.

## Feedback loop

- `mix test` — fast database-backed ExUnit and LiveView tests.
- `mix test test/sprout/domain_test.exs` — focus on one file.
- `mix test --failed` — rerun failures.
- `mix format` — apply source and HEEx formatting.
- `mix credo --strict` — static code analysis.
- `mix coverage` — tests, exported Erlang coverdata, console summary, and HTML reports.
- `mix crap --verbose` — score functions using the last exported coverage data.
- `mix precommit` or `mix quality` — compile, formatting verification, strict Credo,
  coverage, and CRAP gates in the test environment.
- `mix docs` — generate the domain API reference and these guides under `doc/`.
- `mix assets.build` — compile browser assets.

Prefix commands with `mise exec --` if mise is not activated in your shell.
Coverage uses the built-in Erlang/Mix tool; it does not upload source or results.
Run `mix coverage` immediately before standalone CRAP analysis so scores reflect
current source and tests. `mix quality` enforces that order automatically.

## Quality policy

Coverage must reach 80%; CRAP scores must not exceed 30. Coverage measures
executed lines, not branch coverage or assertion quality. CRAP combines complexity
and coverage as `CC² × (1 − coverage_fraction)³ + CC`; it highlights risky functions,
not overall architectural quality. Treat findings as prompts for tests and simpler
code rather than raising thresholds to hide them.

Reports live under `cover/` and are ignored by Git. API docs live under `doc/`.
CI retains reports as artifacts and builds assets and docs without external
coverage credentials. CI configuration lives in `.github/workflows/ci.yml`.

## Domain changes

Keep persistence and invariants inside the owning context. Write an ExUnit test
for the behavior first, confirm it fails, implement the change, then refactor.
Use `Sprout.DataCase` for transactional database tests and `SproutWeb.ConnCase`
with `Phoenix.LiveViewTest` for UI workflows. Sandbox ownership must be explicitly
shared/allowed when testing supervised worker processes. Prefer messages and
synchronous state inspection over sleeps.

Public context functions have `@doc` and `@spec` declarations. Keep units,
error returns, lifecycle transitions, and side effects accurate when changing
code. Pure examples are checked as doctests.

## Land map

The dashboard map displays dashed land parcels and green growing plots over OpenStreetMap.
Choose **Draw a land parcel**, click its perimeter, and **Use boundary** to register
available land. Then choose **Draw a plot**, draw inside a parcel, choose that
parcel in the form, and save its name and declared hectares. Undo removes
the last vertex; clear discards only the unsaved draft. You can also paste
`[latitude, longitude]` pairs into the boundary textarea without using the map.
Clicking a saved plot selects it for sensors and scouting.
Prepare resting soil, mark it ready, and plant its planned next cycle.
A growing plot can have one separate next cycle planned. Plans can be cancelled;
harvest returns the plot to rest, with cycle history retained.

Drawing survives sensor updates. The Land context validates GPS ranges, unique
vertices (3–128), nonzero area, self-intersections, parcel/plot overlaps, and
full plot containment on save. Transaction advisory locks serialize spatial
creation across processes; lifecycle transitions take a plot row lock. Hectares are entered
explicitly; the map does not calculate surveyed area. Boundaries use the existing
local farm-scale geometry and do not support antimeridian-crossing parcels.
Demo coordinates are illustrative, not actual agricultural land holdings.
OpenStreetMap tiles require internet and reveal the viewed area to its tile
service. For a larger deployment, configure a suitable tile provider or self-host
rather than relying on the community tile server.
