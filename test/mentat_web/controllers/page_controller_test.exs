defmodule MentatWeb.PageControllerTest do
  use MentatWeb.ConnCase

  test "GET / redirects to /runs", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/runs"
  end
end
