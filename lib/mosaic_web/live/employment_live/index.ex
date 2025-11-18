defmodule MosaicWeb.EmploymentLive.Index do
  use MosaicWeb, :live_view

  alias Mosaic.Employments

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :employments, Employments.list_employments())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Employments")
  end

  defp get_worker_name(employment) do
    case employment.participations do
      [participation | _] -> participation.participant.properties["name"] || "Unknown"
      [] -> "Unknown"
    end
  end
end
