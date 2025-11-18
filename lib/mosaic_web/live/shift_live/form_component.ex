defmodule MosaicWeb.ShiftLive.FormComponent do
  use MosaicWeb, :live_component

  alias Mosaic.Shifts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Shift details</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="shift-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:start_time]} type="datetime-local" label="Start Time" />
        <.input field={@form[:end_time]} type="datetime-local" label="End Time" />
        <.input field={@form[:location]} type="text" label="Location" />
        <.input field={@form[:department]} type="text" label="Department" />
        <.input field={@form[:notes]} type="textarea" label="Notes" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Draft", "draft"},
            {"Active", "active"},
            {"Completed", "completed"},
            {"Cancelled", "cancelled"}
          ]}
        />
        <.input
          field={@form[:auto_generate_periods]}
          type="checkbox"
          label="Auto-generate work periods and break (break after 4 hours, 30 min duration)"
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save Shift</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{shift: shift} = assigns, socket) do
    {:ok, event_type} = Mosaic.Events.get_event_type_by_name("shift")

    changeset =
      if shift do
        Shifts.change_shift(shift, shift_to_form_attrs(shift))
      else
        # For new shifts, create empty changeset without validation
        Mosaic.Event.changeset(%Mosaic.Event{event_type_id: event_type.id}, %{})
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
      if socket.assigns.shift do
        Shifts.change_shift(socket.assigns.shift, form_to_event_attrs(merged_params))
      else
        {:ok, event_type} = Mosaic.Events.get_event_type_by_name("shift")

        Shifts.change_shift(
          %Mosaic.Event{event_type_id: event_type.id},
          form_to_event_attrs(merged_params)
        )
      end
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"event" => event_params}, socket) do
    save_shift(socket, socket.assigns.action, event_params)
  end

  defp save_shift(socket, :edit, event_params) do
    attrs = form_to_event_attrs(event_params)

    case Shifts.update_shift(socket.assigns.shift.id, attrs) do
      {:ok, shift} ->
        notify_parent({:saved, shift})

        {:noreply,
         socket
         |> put_flash(:info, "Shift updated successfully")
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

  defp save_shift(socket, :new, event_params) do
    attrs = form_to_event_attrs(event_params)

    case Shifts.create_shift(socket.assigns.employment_id, socket.assigns.worker_id, attrs) do
      {:ok, {shift, _participation}} ->
        notify_parent({:saved, shift})

        {:noreply,
         socket
         |> put_flash(:info, "Shift created successfully")
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
      start_time: parse_datetime(params["start_time"]),
      end_time: parse_datetime(params["end_time"]),
      status: params["status"] || "draft",
      auto_generate_periods: params["auto_generate_periods"] == "true",
      location: params["location"],
      department: params["department"],
      notes: params["notes"]
    }
  end

  defp shift_to_form_attrs(shift) do
    %{
      start_time: format_datetime(shift.start_time),
      end_time: format_datetime(shift.end_time),
      status: shift.status,
      location: shift.properties["location"],
      department: shift.properties["department"],
      notes: shift.properties["notes"],
      auto_generate_periods: false
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    # Browser sends datetime-local in format: "2025-11-19T14:47"
    # Try parsing with and without seconds
    case NaiveDateTime.from_iso8601(datetime_string <> ":00") do
      {:ok, naive} ->
        DateTime.from_naive!(naive, "Etc/UTC")

      {:error, _} ->
        case NaiveDateTime.from_iso8601(datetime_string) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          {:error, _} -> nil
        end
    end
  end

  defp parse_datetime(_), do: nil

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end
end
