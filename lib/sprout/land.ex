defmodule Sprout.Land do
  @moduledoc "Plot boundaries use [latitude, longitude] pairs and include their edges. Local farm-scale polygons only."
  import Ecto.Query
  alias Ecto.Adapters.SQL
  alias Ecto.Changeset
  alias Sprout.Land.{Geometry, Parcel, Plot}
  alias Sprout.Repo

  @doc "Lists growing plots in creation order."
  @spec list_plots() :: [Plot.t()]
  def list_plots, do: Repo.all(from p in Plot, order_by: p.id)

  @doc "Fetches a growing plot, raising when absent."
  @spec get_plot!(integer() | String.t()) :: Plot.t()
  def get_plot!(id), do: Repo.get!(Plot, id)

  @doc "Lists available land parcels in creation order."
  @spec list_parcels() :: [Parcel.t()]
  def list_parcels, do: Repo.all(from p in Parcel, order_by: p.id)

  @doc "Fetches a land parcel, raising when absent."
  @spec get_parcel!(integer() | String.t()) :: Parcel.t()
  def get_parcel!(id), do: Repo.get!(Parcel, id)

  @doc "Legacy v1 field read model: fields are growing plots."
  @spec list_fields() :: [Plot.t()]
  def list_fields, do: list_plots()

  @doc "Legacy v1 field lookup: IDs are preserved growing plot IDs."
  @spec get_field!(integer() | String.t()) :: Plot.t()
  def get_field!(id), do: get_plot!(id)

  @doc "Creates available land. Positive-area overlaps are rejected; shared borders are allowed."
  @spec create_parcel(map()) :: {:ok, Parcel.t()} | {:error, Changeset.t()}
  def create_parcel(attrs) do
    spatial_command(fn ->
      %Parcel{} |> Parcel.changeset(attrs) |> reject_overlaps(list_parcels()) |> insert()
    end)
  end

  @doc "Creates a resting plot wholly inside its persisted parcel without overlapping sibling plots."
  @spec create_plot(Parcel.t(), map()) :: {:ok, Plot.t()} | {:error, Changeset.t()}
  def create_plot(%Parcel{id: id}, attrs) do
    spatial_command(fn ->
      parcel = get_parcel!(id)

      %Plot{parcel_id: id}
      |> Plot.changeset(attrs)
      |> validate_inside(parcel)
      |> reject_overlaps(Repo.all(from p in Plot, where: p.parcel_id == ^id))
      |> insert()
    end)
  end

  @doc "Legacy convenience: atomically creates a parcel and a full-parcel plot. Prefer explicit parcel/plot commands."
  @spec create_field(map()) :: {:ok, Plot.t()} | {:error, Changeset.t()}
  def create_field(attrs) do
    spatial_command(fn ->
      parcel = %Parcel{} |> Parcel.changeset(attrs) |> reject_overlaps(list_parcels()) |> insert()
      %Plot{parcel_id: parcel.id} |> Plot.changeset(attrs) |> insert()
    end)
  end

  defp spatial_command(fun) do
    Repo.transaction(fn ->
      SQL.query!(Repo, "SELECT pg_advisory_xact_lock(7712027)", [])
      fun.()
    end)
    |> Sprout.Events.saved(:field)
  end

  defp insert(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp validate_inside(%{valid?: false} = changeset, _), do: changeset

  defp validate_inside(changeset, parcel) do
    points = Changeset.get_field(changeset, :boundary)["points"]

    if Geometry.within?(points, parcel.boundary["points"]),
      do: changeset,
      else: Changeset.add_error(changeset, :boundary, "must stay wholly inside its land parcel")
  end

  defp reject_overlaps(%{valid?: false} = changeset, _), do: changeset

  defp reject_overlaps(changeset, neighbors) do
    points = Changeset.get_field(changeset, :boundary)["points"]

    if Enum.any?(neighbors, &Geometry.overlap?(points, &1.boundary["points"])),
      do:
        Changeset.add_error(
          changeset,
          :boundary,
          "overlaps existing land; shared borders are allowed"
        ),
      else: changeset
  end

  @doc """
  Checks unique GPS vertices, nonzero area, and nonadjacent-edge intersections.

  Vertices are `[latitude, longitude]` pairs; omit a repeated closing vertex.
  The geometry is planar and intended for local farms, not antimeridian crossings.

  ## Examples

      iex> Sprout.Land.valid_boundary?(%{"points" => [[0, 0], [0, 1], [1, 0]]})
      true

      iex> Sprout.Land.valid_boundary?(%{"points" => [[0, 0]]})
      false
  """
  @spec valid_boundary?(term()) :: boolean()
  def valid_boundary?(%{"points" => points})
      when is_list(points) and length(points) in 3..128 do
    valid =
      Enum.all?(points, fn
        [lat, lon] when is_number(lat) and is_number(lon) ->
          lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180

        _ ->
          false
      end)

    valid and length(Enum.uniq(points)) == length(points) and abs(area(points)) > 1.0e-12 and
      simple?(points)
  end

  def valid_boundary?(_), do: false
  defp edges(points), do: Enum.zip(points, tl(points) ++ [hd(points)])

  defp area(points),
    do: Enum.reduce(edges(points), 0, fn {[a, b], [c, d]}, acc -> acc + a * d - c * b end) / 2

  defp cross([a, b], [c, d], [e, f]), do: (c - a) * (f - b) - (d - b) * (e - a)

  defp on_edge?(p, a, b),
    do:
      abs(cross(a, b, p)) < 1.0e-10 and
        Enum.all?([0, 1], fn i ->
          Enum.at(p, i) >= min(Enum.at(a, i), Enum.at(b, i)) - 1.0e-10 and
            Enum.at(p, i) <= max(Enum.at(a, i), Enum.at(b, i)) + 1.0e-10
        end)

  defp simple?(points) do
    segments = Enum.with_index(edges(points))
    n = length(points)

    not Enum.any?(segments, fn {{a, b}, i} ->
      Enum.any?(segments, fn {{c, d}, j} ->
        abs(i - j) > 1 and abs(i - j) != n - 1 and
          intersects?(a, b, c, d)
      end)
    end)
  end

  defp intersects?(a, b, c, d) do
    (cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0) or
      on_edge?(a, c, d) or on_edge?(b, c, d) or on_edge?(c, a, b) or on_edge?(d, a, b)
  end

  @doc """
  Tests a point against a validated field polygon, including its edges.

  Invalid coordinate types return `false`. Call `create_field/1` to validate boundaries before using this query.
  """
  @spec contains?(Plot.t(), number() | nil, number() | nil) :: boolean()
  def contains?(%Plot{boundary: %{"points" => points}}, lat, lon)
      when is_number(lat) and is_number(lon) do
    Enum.any?(edges(points), fn {a, b} -> on_edge?([lat, lon], a, b) end) or
      Enum.reduce(edges(points), false, fn {[a, b], [c, d]}, inside ->
        if b > lon != d > lon and lat < (c - a) * (lon - b) / (d - b) + a,
          do: not inside,
          else: inside
      end)
  end

  def contains?(_, _, _), do: false
end
