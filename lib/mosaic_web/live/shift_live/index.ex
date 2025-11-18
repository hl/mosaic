defmodule MosaicWeb.ShiftLive.Index do
  use MosaicWeb, :live_view

  alias Mosaic.Shifts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :shifts, Shifts.list_shifts())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Shifts")
  end

  defp get_worker_name(shift) do
    case shift.participations do
      [participation | _] -> participation.participant.properties["name"] || "Unknown"
      [] -> "Unknown"
    end
  end
end
