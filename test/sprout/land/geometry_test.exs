defmodule Sprout.Land.GeometryTest do
  use ExUnit.Case, async: true
  alias Sprout.Land.Geometry

  test "positive-area intersection distinguishes neighbors from coincident and crossing polygons" do
    a = [[0, 0], [0, 2], [2, 2], [2, 0]]
    refute Geometry.overlap?(a, [[2, 0], [2, 2], [4, 2], [4, 0]])
    refute Geometry.overlap?(a, [[2, 2], [2, 3], [3, 3]])
    assert Geometry.overlap?(a, Enum.reverse(a))
    assert Geometry.overlap?(a, [[-1, 0.5], [-1, 1.5], [3, 1.5], [3, 0.5]])
    assert Geometry.overlap?(a, [[0, 1], [0, 3], [2, 3], [2, 1]])
    assert Geometry.within?(a, a)
  end

  test "concave polygons and collinear vertices retain containment regardless of winding" do
    parent = [[0, 0], [0, 1], [0, 3], [3, 3], [3, 2], [1, 2], [1, 1], [3, 1], [3, 0]]
    inside = [[0, 0], [0, 1], [3, 1], [3, 0]]
    outside = [[2, 0.5], [2, 2.5], [2.5, 2.5], [2.5, 0.5]]
    assert Geometry.within?(inside, parent)
    assert Geometry.within?(Enum.reverse(inside), Enum.reverse(parent))
    refute Geometry.within?(outside, parent)
    refute Geometry.overlap?(parent, [[1.5, 1.2], [1.5, 1.8], [2, 1.5]])
  end
end
