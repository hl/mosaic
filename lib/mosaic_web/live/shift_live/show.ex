defmodule MosaicWeb.ShiftLive.Show do
  use MosaicWeb, :live_view

  alias Mosaic.{Shifts, Events}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    shift = Shifts.get_shift!(id)
    employment = Events.get_event!(shift.parent_id, preload: [:participations])
    worker = get_worker_from_shift(shift)

    worked_hours = Shifts.calculate_worked_hours(id)
    break_hours = Shifts.calculate_break_hours(id)
    net_hours = Shifts.calculate_net_hours(id)

    {:noreply,
     socket
     |> assign(:page_title, "Shift Details")
     |> assign(:shift, shift)
     |> assign(:employment, employment)
     |> assign(:worker, worker)
     |> assign(:worked_hours, worked_hours)
     |> assign(:break_hours, break_hours)
     |> assign(:net_hours, net_hours)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp apply_action(socket, :edit, _params) do
    socket
  end

  @impl true
  def handle_info({MosaicWeb.ShiftLive.FormComponent, {:saved, _shift}}, socket) do
    shift = Shifts.get_shift!(socket.assigns.shift.id)
    worked_hours = Shifts.calculate_worked_hours(shift.id)
    break_hours = Shifts.calculate_break_hours(shift.id)
    net_hours = Shifts.calculate_net_hours(shift.id)

    {:noreply,
     socket
     |> assign(:shift, shift)
     |> assign(:worked_hours, worked_hours)
     |> assign(:break_hours, break_hours)
     |> assign(:net_hours, net_hours)}
  end

  defp get_worker_from_shift(shift) do
    case shift.participations do
      [participation | _] -> participation.participant
      _ -> nil
    end
  end

  defp format_duration(nil), do: "-"
  defp format_duration(hours), do: "#{Float.round(hours, 2)}h"
end
