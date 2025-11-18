defmodule MosaicWeb.EmploymentLive.FormComponent do
  use MosaicWeb, :live_component

  import MosaicWeb.LiveHelpers

  alias Mosaic.Employments

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Employment period details</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="employment-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:start_time]} type="datetime-local" label="Start Date" />
        <.input field={@form[:end_time]} type="datetime-local" label="End Date" />
        <.input field={@form[:role]} type="text" label="Role" />
        <.input field={@form[:contract_type]} type="text" label="Contract Type" />
        <.input field={@form[:salary]} type="number" label="Salary" step="0.01" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[{"Draft", "draft"}, {"Active", "active"}, {"Ended", "ended"}]}
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save Employment</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{employment: employment} = assigns, socket) do
    {:ok, event_type} = Mosaic.Events.get_event_type_by_name("employment")

    changeset =
      if employment do
        Employments.change_employment(employment, employment_to_form_attrs(employment))
      else
        # For new employments, create empty changeset without validation
        Mosaic.Events.Event.changeset(%Mosaic.Events.Event{event_type_id: event_type.id}, %{})
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    # Merge current form state with new params to preserve all fields
    merged_params =
      if socket.assigns[:form] do
        Map.merge(socket.assigns.form.params || %{}, event_params)
      else
        event_params
      end

    changeset =
      if socket.assigns.employment do
        Employments.change_employment(
          socket.assigns.employment,
          form_to_event_attrs(merged_params)
        )
      else
        {:ok, event_type} = Mosaic.Events.get_event_type_by_name("employment")

        Employments.change_employment(
          %Mosaic.Events.Event{event_type_id: event_type.id},
          form_to_event_attrs(merged_params)
        )
      end
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"event" => event_params}, socket) do
    save_employment(socket, socket.assigns.action, event_params)
  end

  defp save_employment(socket, :edit, event_params) do
    attrs = form_to_event_attrs(event_params)

    case Employments.update_employment(socket.assigns.employment.id, attrs) do
      {:ok, employment} ->
        notify_parent({:saved, employment})

        {:noreply,
         socket
         |> put_flash(:info, "Employment updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_employment(socket, :new, event_params) do
    attrs = form_to_event_attrs(event_params)

    case Employments.create_employment(socket.assigns.worker_id, attrs) do
      {:ok, {employment, _participation}} ->
        notify_parent({:saved, employment})

        {:noreply,
         socket
         |> put_flash(:info, "Employment created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} when is_binary(reason) ->
        {:noreply,
         socket
         |> put_flash(:error, reason)
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    # Don't show errors on initial form load (when action is nil)
    form_opts = [as: :event]

    form_opts =
      if changeset.action == nil, do: Keyword.put(form_opts, :errors, []), else: form_opts

    assign(socket, :form, to_form(changeset, form_opts))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp form_to_event_attrs(params) do
    %{
      "start_time" => parse_datetime_local(params["start_time"]),
      "end_time" => parse_datetime_local(params["end_time"]),
      "status" => params["status"] || "draft",
      "role" => params["role"],
      "contract_type" => params["contract_type"],
      "salary" => params["salary"]
    }
  end

  defp employment_to_form_attrs(employment) do
    %{
      start_time: format_datetime_local(employment.start_time),
      end_time: format_datetime_local(employment.end_time),
      status: employment.status,
      role: get_role(employment),
      contract_type: employment.properties["contract_type"],
      salary: employment.properties["salary"]
    }
  end

  defp get_role(employment) do
    case employment.participations do
      [participation | _] -> participation.role
      _ -> nil
    end
  end
end
