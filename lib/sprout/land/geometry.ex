defmodule Sprout.Land.Geometry do
  @moduledoc "Planar intersection of validated, simple local GPS polygons. Shared edges have zero area."
  @epsilon 1.0e-12

  @doc "Returns true when validated polygons share positive area, including containment."
  @spec overlap?(list(), list()) :: boolean()
  def overlap?(a, b), do: intersection_area(a, b) > @epsilon

  @doc "Checks the entire child polygon against its parent, including concave boundaries."
  @spec within?(list(), list()) :: boolean()
  def within?(child, parent),
    do: abs(area(child)) - intersection_area(child, parent) <= @epsilon

  defp intersection_area(a, b) do
    triangles = triangulate(b)

    for left <- triangulate(a), right <- triangles, reduce: 0.0 do
      sum -> sum + abs(area(clip(left, right)))
    end
  end

  defp area([]), do: 0.0

  defp area([origin | _] = points) do
    Enum.reduce(edges(points), 0.0, fn {a, b}, sum -> sum + cross(origin, a, b) end) / 2
  end

  defp edges(points), do: Enum.zip(points, tl(points) ++ [hd(points)])
  defp cross([x, y], [a, b], [c, d]), do: (a - x) * (d - y) - (b - y) * (c - x)

  defp triangulate(points) do
    points = if area(points) < 0, do: Enum.reverse(points), else: points
    ears(points, [])
  end

  defp ears([a, b, c], acc), do: [[a, b, c] | acc]

  defp ears(points, acc) do
    index =
      Enum.find_index(Enum.with_index(points), fn {b, i} ->
        a = Enum.at(points, i - 1)
        c = Enum.at(points, rem(i + 1, length(points)))
        ear?(a, b, c, points)
      end)

    if is_nil(index), do: raise(ArgumentError, "polygon cannot be triangulated")
    a = Enum.at(points, index - 1)
    b = Enum.at(points, index)
    c = Enum.at(points, rem(index + 1, length(points)))
    ears(List.delete_at(points, index), [[a, b, c] | acc])
  end

  defp ear?(a, b, c, points) do
    turn = cross(a, b, c)
    turn >= 0 and (turn == 0 or not Enum.any?(points -- [a, b, c], &in_triangle?(&1, a, b, c)))
  end

  defp in_triangle?(p, a, b, c),
    do: cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0

  defp clip(subject, triangle) do
    Enum.reduce(edges(triangle), subject, fn {a, b}, polygon -> clip_edge(polygon, a, b) end)
  end

  defp clip_edge([], _, _), do: []

  defp clip_edge(points, a, b) do
    Enum.flat_map(edges(points), fn {p, q} ->
      dp = cross(a, b, p)
      dq = cross(a, b, q)

      case {dp >= 0, dq >= 0} do
        {true, true} -> [q]
        {false, false} -> []
        {true, false} -> [intersection(p, q, dp, dq)]
        {false, true} -> [intersection(p, q, dp, dq), q]
      end
    end)
  end

  defp intersection([x, y], [a, b], dp, dq) do
    t = dp / (dp - dq)
    [x + t * (a - x), y + t * (b - y)]
  end
end
