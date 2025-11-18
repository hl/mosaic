defmodule MosaicWeb.PageController do
  use MosaicWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
