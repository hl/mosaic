defmodule MosaicWeb.WorkersLive.Index do
  use MosaicWeb, :live_view

  alias Mosaic.{Workers, Employments}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :workers, list_workers())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Worker")
    |> assign(:worker, Workers.get_worker!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Worker")
    |> assign(:worker, %Mosaic.Entities.Entity{entity_type: "person", properties: %{}})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Workers")
    |> assign(:worker, nil)
  end

  @impl true
  def handle_info({MosaicWeb.WorkersLive.FormComponent, {:saved, worker}}, socket) do
    {:noreply, stream_insert(socket, :workers, worker)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    worker = Workers.get_worker!(id)
    {:ok, _} = Workers.delete_worker(worker)

    {:noreply, stream_delete(socket, :workers, worker)}
  end

  defp list_workers do
    Workers.list_workers()
    |> Enum.map(fn worker ->
      active_employments = Employments.count_active_employments(worker.id)
      Map.put(worker, :active_employments_count, active_employments)
    end)
  end
end
