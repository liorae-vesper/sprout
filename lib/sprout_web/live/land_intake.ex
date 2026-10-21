defmodule SproutWeb.LandIntake do
  @moduledoc false
  alias Ecto.Changeset
  alias Sprout.Land

  def create(kind, attrs) do
    case Jason.decode(attrs["boundary"] || "") do
      {:ok, points} when is_list(points) ->
        persist(kind, Map.put(attrs, "boundary", %{"points" => points}))

      _ ->
        {:error, :invalid_boundary_json}
    end
  end

  defp persist(:parcel, attrs), do: Land.create_parcel(attrs)

  defp persist(:plot, attrs) do
    case Enum.find(Land.list_parcels(), &(to_string(&1.id) == attrs["parcel_id"])) do
      nil -> {:error, :parcel_required}
      parcel -> Land.create_plot(parcel, attrs)
    end
  end

  def message(:invalid_boundary_json),
    do: "Boundary must be valid JSON: an array of [latitude, longitude] pairs."

  def message(:parcel_required), do: "Choose the land parcel containing this plot."
  def message(:plot_not_ready), do: "Prepare the soil and mark it ready before planting."

  def message(:plot_occupied),
    do: "This plot already has a growing crop. Record its harvest first."

  def message(:outside_field), do: "That location is outside this field. Check your coordinates."

  def message(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {key, value} -> "#{key}: #{Enum.join(value, ", ")}" end)
  end

  def message(_), do: "That change could not be saved. Refresh and try again."
end
