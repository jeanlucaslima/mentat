defmodule MentatWeb.SettingsLiveTest do
  use MentatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "settings page" do
    test "renders the settings page", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings")
      assert html =~ "Generate New Map"
      assert html =~ "Scenarios"
      assert has_element?(view, "button", "GENERATE MAP")
    end

    test "shows world_standard_42 in scenario list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "world_standard_42"
    end

    test "preset selection highlights card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      html = render_click(view, "select_preset", %{"preset" => "standard"})
      assert html =~ "border-success"
    end

    test "auto-fills name from preset and seed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      render_click(view, "select_preset", %{"preset" => "standard"})
      html = render(view)
      assert html =~ "world_standard_random"
    end
  end
end
