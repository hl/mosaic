# Temporal Modeling

> **Navigation:** [📚 Index](index.md) | [🎯 Start Here](00-start-here.md) | [🔴 Architecture](architecture.md)

## Overview

Temporal modeling is central to Mosaic's design. All events have time boundaries, and the system enforces various temporal constraints to ensure data integrity.

## Time Representation

### DateTime Storage
All timestamps use PostgreSQL's `TIMESTAMP WITH TIME ZONE`:
- Stored in UTC
- Converted to local time zones in UI
- Ecto type: `:utc_datetime`

### Event Temporal Bounds
Events have two temporal fields:
- `start_time` - Required, when event begins
- `end_time` - Optional, when event ends (null = ongoing)

## Temporal Relationships

### Point-in-Time Events
Events with same start and end time represent instantaneous occurrences.

Example: Training completion, certification obtained

### Duration Events
Most events have duration (end_time > start_time).

Example: Employment, shift, work period, break

### Ongoing Events
Events without end_time are currently active.

Example: Open-ended employment, shift in progress

## Hierarchical Temporal Constraints

Child events must respect parent temporal boundaries:

```
Employment: [2024-01-01 ─────────────────────── 2024-12-31]
  Shift 1:    [2024-01-15 09:00 ──── 17:00]
    Work:       [09:00 ──── 13:00]
    Break:              [13:00 ─ 13:30]
    Work:                     [13:30 ──── 17:00]
  Shift 2:                  [2024-01-16 09:00 ──── 17:00]
```

### Validation Rules

**Child must start after parent starts:**
```elixir
DateTime.compare(child.start_time, parent.start_time) != :lt
```

**Child must end before parent ends (if parent has end):**
```elixir
case parent.end_time do
  nil -> :ok  # Parent ongoing, any end time allowed
  parent_end ->
    if DateTime.compare(child.end_time, parent_end) == :gt do
      {:error, "exceeds parent bounds"}
    else
      :ok
    end
end
```

## Overlap Detection

### Employment Overlaps
Workers cannot have overlapping active employments:

```elixir
def validate_no_overlapping_employments(worker_id, employment, exclude_id) do
  start_time = employment.start_time
  end_time = employment.end_time

  query =
    if is_nil(end_time) do
      # Ongoing employment overlaps with anything after start
      from [e, et, p] in base_query,
        where: is_nil(e.end_time) or e.end_time > ^start_time
    else
      # Bounded employment checks full overlap logic
      from [e, et, p] in base_query,
        where:
          (is_nil(e.end_time) and e.start_time < ^end_time) or
          (not is_nil(e.end_time) and
            not (e.end_time <= ^start_time or e.start_time >= ^end_time))
    end

  case Repo.one(from e in query, select: count(e.id)) do
    0 -> :ok
    _ -> {:error, "overlapping employments"}
  end
end
```

### Shift Overlaps
Workers cannot have overlapping non-cancelled shifts:

```elixir
def validate_no_shift_overlap(worker_id, shift_attrs) do
  query =
    from [e, et, p] in base_query,
      where:
        e.status != "cancelled" and
        not is_nil(e.start_time) and
        not is_nil(e.end_time) and
        ((e.start_time <= ^shift_start and e.end_time > ^shift_start) or
         (e.start_time < ^shift_end and e.end_time >= ^shift_end) or
         (e.start_time >= ^shift_start and e.end_time <= ^shift_end))

  case Repo.one(from e in query, select: count(e.id)) do
    0 -> :ok
    _ -> {:error, "overlapping shifts"}
  end
end
```

### Overlap Logic

Three cases for overlap between intervals [A_start, A_end] and [B_start, B_end]:

1. **A starts during B:** `A_start < B_end AND A_start >= B_start`
2. **A ends during B:** `A_end > B_start AND A_end <= B_end`
3. **A contains B:** `A_start <= B_start AND A_end >= B_end`

Simplified: Overlaps if NOT (A ends before B starts OR A starts after B ends)
```
NOT (A_end <= B_start OR A_start >= B_end)
```

## Duration Calculations

### Event Duration
```elixir
def duration_hours(%Event{start_time: start_time, end_time: end_time}) do
  if start_time && end_time do
    DateTime.diff(end_time, start_time, :second) / 3600
  else
    nil
  end
end
```

### Worked Hours
Sum of work_period durations within a shift:
```elixir
def calculate_worked_hours(shift_id) do
  query =
    from e in Event,
      join: et in assoc(e, :event_type),
      where: e.parent_id == ^shift_id and et.name == "work_period"

  Repo.all(query)
  |> Enum.reduce(0, fn event, acc ->
    case Event.duration_hours(event) do
      nil -> acc
      hours -> acc + hours
    end
  end)
end
```

### Net Hours
Worked hours minus unpaid breaks:
```elixir
def calculate_net_hours(shift_id) do
  worked = calculate_worked_hours(shift_id)
  unpaid_breaks = calculate_unpaid_break_hours(shift_id)
  worked - unpaid_breaks
end
```

## Temporal Queries

### Events in Time Range
```elixir
from e in Event,
  where: e.start_time >= ^from_date,
  where: e.start_time <= ^to_date
```

### Active Events at Point in Time
```elixir
from e in Event,
  where: e.start_time <= ^datetime,
  where: is_nil(e.end_time) or e.end_time > ^datetime,
  where: e.status == "active"
```

### Event Timeline
```elixir
from e in Event,
  where: e.parent_id == ^parent_id,
  order_by: [asc: e.start_time],
  preload: [:event_type]
```

## Participation Time Bounds

Participations can have their own temporal bounds within the event:

```elixir
# Worker joined shift mid-way
%Participation{
  event_id: shift_id,
  participant_id: worker_id,
  start_time: ~U[2024-01-15 10:00:00Z],  # Shift started at 09:00
  end_time: ~U[2024-01-15 17:00:00Z]      # Shift ends at 17:00
}
```

This allows modeling:
- Late arrivals
- Early departures
- Shift coverage changes
- Multi-worker events

## Status Transitions

Status field tracks event lifecycle in time:

```
draft → active → completed
  ↓       ↓
cancelled cancelled
```

Certain operations are only valid in certain states:
- Can only activate draft events
- Can only complete active events
- Cancelled events cannot be reactivated

## Date vs DateTime

The system uses DateTime throughout (not Date):
- More precise for scheduling
- Handles cross-timezone scenarios
- Allows minute-level work tracking

UI can display as date-only when appropriate (employment start/end dates).

## Future Enhancements

### Recurrence
Support for recurring events:
- Weekly shifts
- Bi-weekly pay periods
- Annual reviews

### Timezone Support
Currently UTC-only, future:
- Store user timezone preferences
- Display in local time
- Handle DST transitions

### Temporal Audit
Track when temporal fields change:
- Shift rescheduling history
- Employment period extensions
- Status transition timestamps

## See Also

- [01-events-and-participations.md](01-events-and-participations.md) - Core event model
- [09-scheduling-model.md](09-scheduling-model.md) - Shift implementation with temporal validation
- [03-event-types.md](03-event-types.md) - Event type system and validation patterns
