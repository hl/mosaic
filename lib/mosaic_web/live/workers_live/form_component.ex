defmodule MosaicWeb.WorkersLive.FormComponent do
  use MosaicWeb, :live_component

  alias Mosaic.Workers

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage worker records.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        as={:worker}
        id="worker-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:phone]} type="text" label="Phone" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Worker</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{worker: worker} = assigns, socket) do
    changeset = Workers.change_worker(worker, worker_attrs_from_properties(worker))

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"worker" => worker_params}, socket) do
    changeset =
      socket.assigns.worker
      |> Workers.change_worker(build_properties(worker_params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"worker" => worker_params}, socket) do
    save_worker(socket, socket.assigns.action, worker_params)
  end

  defp save_worker(socket, :edit, worker_params) do
    properties = build_properties(worker_params)

    case Workers.update_worker(socket.assigns.worker, %{properties: properties}) do
      {:ok, worker} ->
        notify_parent({:saved, worker})

        {:noreply,
         socket
         |> put_flash(:info, "Worker updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_worker(socket, :new, worker_params) do
    properties = build_properties(worker_params)

    case Workers.create_worker(%{properties: properties}) do
      {:ok, worker} ->
        notify_parent({:saved, worker})

        {:noreply,
         socket
         |> put_flash(:info, "Worker created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :worker))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp build_properties(worker_params) do
    %{
      "name" => worker_params["name"],
      "email" => worker_params["email"],
      "phone" => worker_params["phone"]
    }
  end

  defp worker_attrs_from_properties(%Mosaic.Entities.Entity{properties: properties}) do
    %{
      "name" => properties["name"],
      "email" => properties["email"],
      "phone" => properties["phone"]
    }
  end

  defp worker_attrs_from_properties(_), do: %{}
end
