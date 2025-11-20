defmodule Mosaic.Payroll do
  @moduledoc """
  The Payroll context handles payroll piece subdivision of clock periods.

  Payroll pieces subdivide clock periods for different cost centers, job codes,
  union rules, or rate types (regular, overtime, double_time).
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Events.Event

  @doc """
  Creates a payroll piece within a clock period.

  Attrs should include:
  - start_time (required)
  - end_time (required)
  - properties (optional), which can include:
    - cost_center: Department or cost center code
    - job_code: Specific job or task code
    - union_rule: Union rule or agreement reference
    - rate_type: "regular", "overtime", "double_time", etc.
    - Any other custom payroll-related metadata

  Returns {:ok, payroll_piece} or {:error, changeset}.
  """
  def create_payroll_piece(clock_period_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, clock_period} <- validate_clock_period(clock_period_id),
           :ok <- validate_payroll_piece_in_period(attrs, clock_period),
           {:ok, event_type} <- Events.get_event_type_by_name("payroll_piece"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "parent_id" => clock_period_id,
             "start_time" => attrs["start_time"] || attrs[:start_time],
             "end_time" => attrs["end_time"] || attrs[:end_time],
             "status" => attrs["status"] || attrs[:status] || "active",
             "properties" => attrs["properties"] || attrs[:properties] || %{}
           },
           {:ok, event} <- Events.create_event(event_attrs) do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Lists all payroll pieces for a clock period.
  """
  def list_payroll_pieces(clock_period_id) do
    from(e in Event,
      join: et in assoc(e, :event_type),
      where: et.name == "payroll_piece",
      where: e.parent_id == ^clock_period_id,
      order_by: [asc: e.start_time],
      preload: [:event_type]
    )
    |> Repo.all()
  end

  @doc """
  Calculates total hours for payroll pieces grouped by rate type.

  Returns a map like: %{"regular" => 6.5, "overtime" => 1.5}
  """
  def calculate_hours_by_rate_type(clock_period_id) do
    list_payroll_pieces(clock_period_id)
    |> Enum.group_by(fn piece ->
      piece.properties["rate_type"] || "regular"
    end)
    |> Enum.map(fn {rate_type, pieces} ->
      total_hours =
        pieces
        |> Enum.map(&Event.duration_hours/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.sum()

      {rate_type, total_hours}
    end)
    |> Map.new()
  end

  # Private helper functions

  defp validate_clock_period(clock_period_id) do
    Events.validate_event_type(clock_period_id, "clock_period", preload: [:event_type])
  end

  defp validate_payroll_piece_in_period(piece_attrs, clock_period) do
    piece_start = piece_attrs[:start_time] || piece_attrs["start_time"]
    piece_end = piece_attrs[:end_time] || piece_attrs["end_time"]

    cond do
      is_nil(piece_start) ->
        {:error, "Start time is required"}

      is_nil(piece_end) ->
        {:error, "End time is required"}

      DateTime.compare(piece_start, clock_period.start_time) == :lt ->
        {:error, "Payroll piece starts before clock period"}

      DateTime.compare(piece_end, clock_period.end_time) == :gt ->
        {:error, "Payroll piece ends after clock period"}

      true ->
        :ok
    end
  end
end
