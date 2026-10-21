defmodule SproutWeb.PageControllerTest do
  use SproutWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Little things. Growing beautifully."
  end
end
