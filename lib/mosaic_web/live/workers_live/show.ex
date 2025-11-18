defmodule MosaicWeb.WorkersLive.Show do
  use MosaicWeb, :live_view

  alias Mosaic.{Entities, Employments}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    worker = Entities.get_entity!(id)
    employments = Employments.list_employments_for_worker(id)

    {:noreply,
     socket
     |> assign(:page_title, "Worker: #{worker.properties["name"]}")
     |> assign(:worker, worker)
     |> assign(:employments, employments)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:employment, nil)
  end

  defp apply_action(socket, :new_employment, _params) do
    socket
    |> assign(:employment, nil)
  end

  defp apply_action(socket, :edit, _params) do
    socket
  end

  @impl true
  def handle_info({MosaicWeb.WorkersLive.FormComponent, {:saved, _worker}}, socket) do
    worker = Entities.get_entity!(socket.assigns.worker.id)
    {:noreply, assign(socket, :worker, worker)}
  end

  @impl true
  def handle_info({MosaicWeb.EmploymentLive.FormComponent, {:saved, _employment}}, socket) do
    employments = Employments.list_employments_for_worker(socket.assigns.worker.id)
    {:noreply, assign(socket, :employments, employments)}
  end
end
