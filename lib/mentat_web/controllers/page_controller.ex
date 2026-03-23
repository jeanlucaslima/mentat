defmodule MentatWeb.PageController do
  use MentatWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/runs")
  end
end
