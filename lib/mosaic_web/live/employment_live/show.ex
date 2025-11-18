defmodule MosaicWeb.EmploymentLive.Show do
  use MosaicWeb, :live_view

  alias Mosaic.{Employments, Shifts}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    employment = Employments.get_employment!(id)
    shifts = Shifts.list_shifts_for_employment(id)
    worker = get_worker_from_employment(employment)

    {:noreply,
     socket
     |> assign(:page_title, "Employment Period")
     |> assign(:employment, employment)
     |> assign(:worker, worker)
     |> assign(:shifts, shifts)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp apply_action(socket, :edit, _params) do
    socket
  end

  defp apply_action(socket, :new_shift, _params) do
    socket
  end

  @impl true
  def handle_info({MosaicWeb.EmploymentLive.FormComponent, {:saved, _employment}}, socket) do
    employment = Employments.get_employment!(socket.assigns.employment.id)
    {:noreply, assign(socket, :employment, employment)}
  end

  @impl true
  def handle_info({MosaicWeb.ShiftLive.FormComponent, {:saved, _shift}}, socket) do
    shifts = Shifts.list_shifts_for_employment(socket.assigns.employment.id)
    {:noreply, assign(socket, :shifts, shifts)}
  end

  defp get_worker_from_employment(employment) do
    case employment.participations do
      [participation | _] -> participation.participant
      _ -> nil
    end
  end

  defp format_duration(nil), do: "-"
  defp format_duration(hours), do: "#{Float.round(hours, 2)}h"
end
