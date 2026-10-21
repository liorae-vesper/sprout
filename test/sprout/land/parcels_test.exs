defmodule Sprout.Land.ParcelsTest do
  use Sprout.DataCase
  alias Sprout.Land

  defp attrs(name, points), do: %{name: name, area_ha: 1, boundary: %{"points" => points}}
  defp square(x, y), do: [[x, y], [x + 1, y], [x + 1, y + 1], [x, y + 1]]

  test "parcels may share borders or be disconnected but cannot overlap or contain each other" do
    {:ok, _} = Land.create_parcel(attrs("Home", square(0, 0)))
    assert {:ok, _} = Land.create_parcel(attrs("Neighbor", square(1, 0)))
    assert {:ok, _} = Land.create_parcel(attrs("Elsewhere", square(4, 4)))
    assert {:error, changeset} = Land.create_parcel(attrs("Crossing", square(0.5, 0.5)))
    assert errors_on(changeset).boundary
    assert {:error, _} = Land.create_parcel(attrs("Duplicate", square(0, 0)))
    assert {:error, _} = Land.create_parcel(attrs("Inside", [[0.1, 0.1], [0.2, 0.1], [0.1, 0.2]]))
  end

  test "plots belong to a parcel and may share edges but cannot overlap or leave it" do
    {:ok, parcel} = Land.create_parcel(attrs("Home", [[0, 0], [0, 3], [3, 3], [3, 0]]))
    {:ok, plot} = Land.create_plot(parcel, attrs("Mint", square(0, 0)))
    assert plot.parcel_id == parcel.id
    assert plot.soil_status == :resting
    assert {:ok, _} = Land.create_plot(parcel, attrs("Kale", square(1, 0)))
    assert {:error, _} = Land.create_plot(parcel, attrs("Overlap", square(0.5, 0.5)))
    assert {:error, _} = Land.create_plot(parcel, attrs("Outside", square(2.5, 0)))
  end

  test "concave parcel containment checks the whole plot, not just vertices" do
    {:ok, parcel} =
      Land.create_parcel(
        attrs("U-shaped", [[0, 0], [0, 3], [3, 3], [3, 2], [1, 2], [1, 1], [3, 1], [3, 0]])
      )

    assert {:error, _} =
             Land.create_plot(
               parcel,
               attrs("Across notch", [[2, 0.5], [2, 2.5], [2.5, 2.5], [2.5, 0.5]])
             )

    assert {:ok, _} =
             Land.create_plot(parcel, attrs("Along edge", [[0, 0], [0, 1], [3, 1], [3, 0]]))
  end

  test "plot intake ignores forged ownership and readiness and rejects oversized boundary lists" do
    {:ok, parcel} = Land.create_parcel(attrs("Home", square(0, 0)))

    {:ok, plot} =
      Land.create_plot(
        parcel,
        Map.merge(attrs("Mint", square(0, 0)), %{parcel_id: -1, soil_status: :ready})
      )

    assert plot.parcel_id == parcel.id
    assert plot.soil_status == :resting
    refute Land.valid_boundary?(%{"points" => Enum.map(0..128, &[&1 / 100, 0])})
  end
end
