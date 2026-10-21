defmodule Sprout.Land.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Sprout.{Cultivation, Land, Repo}
  alias Sprout.Cultivation.Crop
  alias Sprout.Land.{Parcel, Plot}

  setup do
    supervisor = start_supervised!(Task.Supervisor)
    name = "concurrency-#{System.unique_integer([:positive])}"

    attrs = %{
      name: name,
      area_ha: 2,
      boundary: %{"points" => [[40, 20], [40, 21], [41, 21], [41, 20]]}
    }

    on_exit(fn ->
      unboxed(fn ->
        parcels = from p in Parcel, where: p.name == ^name, select: p.id
        plots = from p in Plot, where: p.parcel_id in subquery(parcels), select: p.id
        Repo.delete_all(from c in Crop, where: c.field_id in subquery(plots))
        Repo.delete_all(from p in Plot, where: p.id in subquery(plots))
        Repo.delete_all(from p in Parcel, where: p.id in subquery(parcels))
      end)
    end)

    %{supervisor: supervisor, attrs: attrs}
  end

  test "concurrent overlapping parcel registrations commit only one", %{
    supervisor: sup,
    attrs: attrs
  } do
    results = race(sup, fn -> Land.create_parcel(attrs) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Ecto.Changeset{}}, &1)) == 1
  end

  test "concurrent overlapping plots commit only one", %{supervisor: sup, attrs: attrs} do
    {:ok, parcel} = unboxed(fn -> Land.create_parcel(attrs) end)
    results = race(sup, fn -> Land.create_plot(parcel, attrs) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Ecto.Changeset{}}, &1)) == 1
  end

  test "concurrent planting of a stale planned cycle commits one transition", %{
    supervisor: sup,
    attrs: attrs
  } do
    {:ok, cycle} =
      unboxed(fn ->
        {:ok, plot} = Land.create_field(attrs)
        {:ok, plot} = Cultivation.transition_plot(plot, :preparing)
        {:ok, plot} = Cultivation.transition_plot(plot, :ready)

        Cultivation.plan_crop(plot, %{
          name: "Mint",
          variety: "Green",
          baseline_kg_ha: 1000,
          planned_on: Date.utc_today()
        })
      end)

    results = race(sup, fn -> Cultivation.transition(cycle, :growing) end)
    assert Enum.count(results, &match?({:ok, %{status: :growing}}, &1)) == 1
    assert {:error, :stale_cycle} in results
  end

  defp race(supervisor, fun) do
    Enum.map(1..2, fn _ -> Task.Supervisor.async_nolink(supervisor, fn -> unboxed(fun) end) end)
    |> Task.await_many()
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
