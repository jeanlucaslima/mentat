defmodule MentatWeb.PageController do
  use MentatWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
