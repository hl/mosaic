# Scheduling & Timekeeping Implementation Guide

> **Navigation:** [📚 Index](index.md) | [🎯 Start Here](00-start-here.md) | [🔴 Architecture](architecture.md)

## Purpose
Implementation roadmap for building location hierarchies, schedules, shift assignments and timekeeping in Mosaic using the event/participation spine.

## Prerequisites
- `Mosaic.Events` context with `Event` schema (at `/mnt/project/event.ex`, `/mnt/project/events.ex`)
- `Mosaic.Participations` context with `Participation` schema (at `/mnt/project/participation.ex`, `/mnt/project/participations.ex`)
- `Mosaic.Entities` context with `Entity` schema (at `/mnt/project/entity.ex`, `/mnt/project/entities.ex`)
- Event types system (see `03-event-types.md`)
- Properties pattern (see `08-properties-pattern.md`)

## ⚠️ Important: Always Use Domain Contexts

Throughout this guide, remember:
- ✅ Use `Mosaic.Shifts.create_shift(...)` NOT `Events.create_event(...)`
- ✅ Use `Mosaic.Workers.create_worker(...)` NOT `Entities.create_entity(...)`
- ✅ Use `Mosaic.Locations.create_location(...)` NOT `Entities.create_entity(...)`

Domain contexts contain business logic and validation.

---

## Implementation Step 1: Location Hierarchy

### Create Location Entity Type

**Database**: No new tables needed. Locations are just `entities` rows.

**Wrapper Module**: `/mnt/project/location.ex` (already exists)
**Context Module**: `/mnt/project/locations.ex` (already exists)

### Using the Locations Context

```elixir
# ✅ CORRECT - Use Locations context
{:ok, building} = Mosaic.Locations.create_location(%{
  "properties" => %{
    "name" => "Building A",
    "address" => "123 Main Street",
    "capacity" => 100
  }
})

{:ok, floor} = Mosaic.Locations.create_location(%{
  "properties" => %{
    "name" => "Floor 1",
    "address" => "Building A - Floor 1",
    "capacity" => 50
  }
})
```

### Location Hierarchy Module

Extend the Locations context to support hierarchy:

```elixir
# Add to lib/mosaic/locations.ex

defmodule Mosaic.Locations do
  # ... existing functions ...
  
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Events.Event
  alias Mosaic.Events.EventType
  alias Mosaic.Participations.Participation
  
  @doc """
  Links a child location to a parent via a location_membership event.
  """
  def set_parent(child_id, parent_id, start_time \\ DateTime.utc_now()) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name("location_membership"),
           attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => start_time,
             "status" => "active"
           },
           {:ok, event} <- Events.create_event(attrs),
           # Create parent participation
           parent_attrs <- %{
             "participant_id" => parent_id,
             "event_id" => event.id,
             "participation_type" => "parent_location"
           },
           {:ok, _parent_participation} <-
             %Participation{}
             |> Participation.changeset(parent_attrs)
             |> Repo.insert(),
           # Create child participation
           child_attrs <- %{
             "participant_id" => child_id,
             "event_id" => event.id,
             "participation_type" => "child_location"
           },
           {:ok, _child_participation} <-
             %Participation{}
             |> Participation.changeset(child_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  @doc """
  Gets the current parent for a location at a given time.
  """
  def get_parent(location_id, at_time \\ DateTime.utc_now()) do
    query =
      from e in Event,
        join: et in EventType, on: e.event_type_id == et.id,
        join: p_child in Participation, on: p_child.event_id == e.id,
        join: p_parent in Participation, on: p_parent.event_id == e.id,
        where: et.name == "location_membership",
        where: p_child.participant_id == ^location_id,
        where: p_child.participation_type == "child_location",
        where: p_parent.participation_type == "parent_location",
        where: e.start_time <= ^at_time,
        where: is_nil(e.end_time) or e.end_time > ^at_time,
        select: p_parent.participant_id

    Repo.one(query)
  end
end
```

### Usage Example

```elixir
# ✅ Create locations using Locations context
{:ok, building} = Mosaic.Locations.create_location(%{
  "properties" => %{
    "name" => "Building A",
    "address" => "123 Main St"
  }
})

{:ok, floor} = Mosaic.Locations.create_location(%{
  "properties" => %{
    "name" => "Floor 1",
    "address" => "Building A - Floor 1"
  }
})

# Set hierarchy
{:ok, _membership} = Mosaic.Locations.set_parent(floor.id, building.id)

# Query hierarchy
parent_id = Mosaic.Locations.get_parent(floor.id)
```

---

## Implementation Step 2: Schedule Events

### Create Schedule Event Type

**Database**: No new tables. Schedules are `events` rows.

**Event Type Definition**: Add to seeds

```elixir
Repo.insert!(%Mosaic.Events.EventType{
  name: "schedule",
  category: "planning",
  can_nest: false,
  can_have_children: true,  # Can parent shifts
  requires_participation: true  # Must link to location
})
```

### Create Schedules Context

**Module**: `lib/mosaic/schedules.ex`

```elixir
defmodule Mosaic.Schedules do
  @moduledoc """
  Manages schedule events that parent shifts.
  """
  
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Participations.Participation
  
  @doc """
  Creates a schedule for a location.
  """
  def create_schedule(location_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name("schedule"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => attrs.start_time,
             "end_time" => attrs.end_time,
             "status" => "draft",
             "properties" => %{
               "timezone" => attrs[:timezone] || "UTC",
               "recurrence_rule" => attrs[:recurrence_rule],
               "coverage_notes" => attrs[:coverage_notes],
               "version" => 1
             }
           },
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => location_id,
             "event_id" => event.id,
             "participation_type" => "location_scope"
           },
           {:ok, _participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  @doc """
  Publishes a schedule (changes status to active).
  """
  def publish_schedule(schedule_id) do
    schedule = Events.get_event!(schedule_id)
    
    Events.update_event(schedule, %{
      "status" => "active",
      "properties" => Map.merge(schedule.properties, %{
        "published_at" => DateTime.utc_now()
      })
    })
  end
  
  @doc """
  Lists all schedules for a location.
  """
  def list_schedules_for_location(location_id) do
    from(e in Events.Event,
      join: et in Events.EventType, on: e.event_type_id == et.id,
      join: p in Participation, on: p.event_id == e.id,
      where: et.name == "schedule",
      where: p.participant_id == ^location_id,
      where: p.participation_type == "location_scope",
      order_by: [desc: e.start_time],
      preload: [:event_type, :participations]
    )
    |> Repo.all()
  end
end
```

### Usage Example

```elixir
# ✅ Create location first
{:ok, location} = Mosaic.Locations.create_location(%{
  "properties" => %{
    "name" => "Warehouse 1",
    "address" => "100 Industrial Dr"
  }
})

# ✅ Create schedule using Schedules context
{:ok, schedule} = Mosaic.Schedules.create_schedule(location.id, %{
  start_time: ~U[2024-01-01 00:00:00Z],
  end_time: ~U[2024-01-31 23:59:59Z],
  timezone: "America/New_York"
})

# Publish when ready
{:ok, published} = Mosaic.Schedules.publish_schedule(schedule.id)
```

---

## Implementation Step 3: Shifts Under Schedules

### Event Type Already Exists

The shift event type is already defined (see `shift.ex` and `shifts.ex`).

### Extend Shifts Context for Schedules

```elixir
# Add to lib/mosaic/shifts.ex

defmodule Mosaic.Shifts do
  # ... existing functions ...
  
  @doc """
  Creates a shift within a schedule (instead of employment).
  Note: This is an alternative hierarchy to employment -> shift.
  """
  def create_shift_in_schedule(schedule_id, worker_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, schedule} <- validate_schedule(schedule_id),
           :ok <- validate_shift_in_schedule(attrs, schedule),
           :ok <- validate_no_shift_overlap(worker_id, attrs),
           {:ok, event_type} <- Events.get_event_type_by_name("shift"),
           attrs <- Map.merge(attrs, %{
             "event_type_id" => event_type.id,
             "parent_id" => schedule_id
           }),
           {:ok, shift} <- Events.create_event(attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => shift.id,
             "participation_type" => "worker",
             "properties" => %{}
           },
           {:ok, participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        {shift, participation}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  defp validate_schedule(schedule_id) do
    Events.validate_event_type(schedule_id, "schedule")
  end
  
  defp validate_shift_in_schedule(shift_attrs, schedule) do
    shift_start = shift_attrs[:start_time] || shift_attrs["start_time"]
    shift_end = shift_attrs[:end_time] || shift_attrs["end_time"]
    
    cond do
      is_nil(shift_start) -> {:error, "Shift start time is required"}
      is_nil(shift_end) -> {:error, "Shift end time is required"}
      DateTime.compare(shift_start, schedule.start_time) == :lt ->
        {:error, "Shift starts before schedule period"}
      not is_nil(schedule.end_time) and DateTime.compare(shift_end, schedule.end_time) == :gt ->
        {:error, "Shift ends after schedule period"}
      true -> :ok
    end
  end
end
```

### Usage Example

```elixir
# ✅ Create worker
{:ok, worker} = Mosaic.Workers.create_worker(%{
  "properties" => %{
    "name" => "Jane Smith",
    "email" => "jane@example.com"
  }
})

# ✅ Create shift using Shifts context
{:ok, {shift, participation}} = Mosaic.Shifts.create_shift_in_schedule(
  schedule.id,
  worker.id,
  %{
    "start_time" => ~U[2024-01-15 09:00:00Z],
    "end_time" => ~U[2024-01-15 17:00:00Z],
    "location" => "Warehouse 1",
    "department" => "Receiving"
  }
)
```

---

## Implementation Step 4: Work Periods, Breaks, Tasks

### Create Child Event Types

```elixir
# Work period - paid time within shift
Repo.insert!(%Mosaic.Events.EventType{
  name: "work_period",
  category: "work",
  can_nest: false,
  can_have_children: false
})

# Break - may be paid or unpaid
Repo.insert!(%Mosaic.Events.EventType{
  name: "break",
  category: "work",
  can_nest: false,
  can_have_children: false
})

# Task - specific work assignment
Repo.insert!(%Mosaic.Events.EventType{
  name: "task",
  category: "work",
  can_nest: false,
  can_have_children: false
})
```

### Extend Shifts Context

These are already in the actual `Mosaic.Shifts` context, but here's the pattern:

```elixir
# Add to lib/mosaic/shifts.ex

defmodule Mosaic.Shifts do
  # ... existing functions including auto_generate_periods ...
  
  @doc """
  Adds a break to an existing shift.
  """
  def add_break(shift_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, shift} <- validate_shift(shift_id),
           {:ok, event_type} <- Events.get_event_type_by_name("break"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "parent_id" => shift_id,
             "start_time" => attrs.start_time,
             "end_time" => attrs.end_time,
             "status" => "active",
             "properties" => %{
               "is_paid" => attrs[:is_paid] || false
             }
           },
           {:ok, event} <- Events.create_event(event_attrs) do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
```

### Usage Example

```elixir
# ✅ Create shift first (using Shifts context)
{:ok, {shift, _}} = Mosaic.Shifts.create_shift(employment_id, worker_id, %{
  "start_time" => ~U[2024-01-15 09:00:00Z],
  "end_time" => ~U[2024-01-15 17:00:00Z],
  "location" => "Warehouse 1"
})

# ✅ Add break using Shifts context
{:ok, break_event} = Mosaic.Shifts.add_break(shift.id, %{
  start_time: ~U[2024-01-15 12:00:00Z],
  end_time: ~U[2024-01-15 12:30:00Z],
  is_paid: false
})

# ✅ Or use auto_generate_periods (already in Shifts context)
{:ok, periods} = Mosaic.Shifts.auto_generate_periods(shift.id, worker.id)
```

---

## Implementation Step 5: Clock Events (Actual Time)

### Create Clock Event Types

```elixir
# Raw punch
Repo.insert!(%Mosaic.Events.EventType{
  name: "clock_event",
  category: "timekeeping",
  can_nest: false,
  can_have_children: false
})

# Consolidated time period
Repo.insert!(%Mosaic.Events.EventType{
  name: "clock_period",
  category: "timekeeping",
  can_nest: false,
  can_have_children: true  # Can parent payroll_pieces
})
```

### Module: `lib/mosaic/timekeeping.ex`

```elixir
defmodule Mosaic.Timekeeping do
  @moduledoc """
  Manages clock events and actual worked time.
  """
  
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Events.Event
  alias Mosaic.Events.EventType
  alias Mosaic.Participations.Participation
  
  @doc """
  Records a clock-in event for a worker.
  """
  def clock_in(worker_id, opts \\ []) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      
      with {:ok, event_type} <- Events.get_event_type_by_name("clock_event"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => now,
             "end_time" => now,  # Point in time
             "status" => "active",
             "properties" => %{
               "event_type" => "in",
               "device_id" => opts[:device_id],
               "location_id" => opts[:location_id],
               "gps_coords" => opts[:gps_coords]
             }
           },
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "worker"
           },
           {:ok, _participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  @doc """
  Records a clock-out event for a worker.
  """
  def clock_out(worker_id, opts \\ []) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      
      with {:ok, event_type} <- Events.get_event_type_by_name("clock_event"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => now,
             "end_time" => now,
             "status" => "active",
             "properties" => %{
               "event_type" => "out",
               "device_id" => opts[:device_id],
               "location_id" => opts[:location_id],
               "gps_coords" => opts[:gps_coords]
             }
           },
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "worker"
           },
           {:ok, _participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  @doc """
  Creates a clock period from clock in/out events.
  """
  def create_clock_period(worker_id, clock_in_event_id, clock_out_event_id) do
    Repo.transaction(fn ->
      clock_in = Events.get_event!(clock_in_event_id)
      clock_out = Events.get_event!(clock_out_event_id)
      
      with {:ok, event_type} <- Events.get_event_type_by_name("clock_period"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => clock_in.start_time,
             "end_time" => clock_out.start_time,
             "status" => "active",
             "properties" => %{
               "clock_in_event_id" => clock_in_event_id,
               "clock_out_event_id" => clock_out_event_id,
               "planned_shift_reference" => find_matching_shift(worker_id, clock_in.start_time)
             }
           },
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "worker"
           },
           {:ok, _participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  defp find_matching_shift(worker_id, clock_time) do
    from(e in Event,
      join: et in EventType, on: e.event_type_id == et.id,
      join: p in Participation, on: p.event_id == e.id,
      where: et.name == "shift",
      where: p.participant_id == ^worker_id,
      where: p.participation_type == "worker",
      where: e.start_time <= ^clock_time,
      where: e.end_time >= ^clock_time,
      select: e.id
    )
    |> Repo.one()
  end
end
```

### Usage Example

```elixir
# ✅ Use Timekeeping context
{:ok, clock_in_event} = Mosaic.Timekeeping.clock_in(worker.id, 
  device_id: "terminal_01",
  location_id: location.id
)

# Later...
{:ok, clock_out_event} = Mosaic.Timekeeping.clock_out(worker.id,
  device_id: "terminal_01"
)

# Create clock period
{:ok, period} = Mosaic.Timekeeping.create_clock_period(
  worker.id,
  clock_in_event.id,
  clock_out_event.id
)
```

---

## Implementation Step 6: Payroll Pieces

### Create Payroll Piece Event Type

```elixir
Repo.insert!(%Mosaic.Events.EventType{
  name: "payroll_piece",
  category: "payroll",
  can_nest: false,
  can_have_children: false
})
```

### Module: `lib/mosaic/payroll.ex`

```elixir
defmodule Mosaic.Payroll do
  @moduledoc """
  Subdivides clock_periods into payroll pieces.
  """
  
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Events
  
  @doc """
  Creates a payroll piece within a clock period.
  """
  def create_payroll_piece(clock_period_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name("payroll_piece"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "parent_id" => clock_period_id,
             "start_time" => attrs.start_time,
             "end_time" => attrs.end_time,
             "status" => "active",
             "properties" => %{
               "cost_center" => attrs[:cost_center],
               "job_code" => attrs[:job_code],
               "union_rule" => attrs[:union_rule],
               "rate_type" => attrs[:rate_type]  # "regular", "overtime", "double_time"
             }
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
    from(e in Events.Event,
      join: et in Events.EventType, on: e.event_type_id == et.id,
      where: et.name == "payroll_piece",
      where: e.parent_id == ^clock_period_id,
      order_by: [asc: e.start_time]
    )
    |> Repo.all()
  end
end
```

### Usage Example

```elixir
# ✅ Use Payroll context
{:ok, piece} = Mosaic.Payroll.create_payroll_piece(clock_period.id, %{
  start_time: ~U[2024-01-15 09:00:00Z],
  end_time: ~U[2024-01-15 13:00:00Z],
  cost_center: "WAREHOUSE",
  job_code: "RECEIVING",
  rate_type: "regular"
})
```

---

## Implementation Step 7: Compensation Rates

### Create Compensation Event Type

```elixir
Repo.insert!(%Mosaic.Events.EventType{
  name: "compensation_rate",
  category: "hr",
  can_nest: false,
  can_have_children: false
})
```

### Extend Employments Context

```elixir
# Add to lib/mosaic/employments.ex

defmodule Mosaic.Employments do
  # ... existing functions ...
  
  @doc """
  Adds a compensation rate to an employment.
  """
  def add_compensation_rate(employment_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name("compensation_rate"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "parent_id" => employment_id,
             "start_time" => attrs.effective_date,
             "end_time" => nil,
             "status" => "active",
             "properties" => %{
               "currency" => attrs[:currency] || "USD",
               "base_rate" => attrs.base_rate,
               "overtime_multiplier" => attrs[:overtime_multiplier] || 1.5,
               "rate_unit" => attrs.rate_unit  # "hour", "day", "salary"
             }
           },
           {:ok, event} <- Events.create_event(event_attrs) do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  @doc """
  Gets the active compensation rate for an employment.
  """
  def get_active_rate(employment_id, at_time \\ DateTime.utc_now()) do
    from(e in Events.Event,
      join: et in Events.EventType, on: e.event_type_id == et.id,
      where: et.name == "compensation_rate",
      where: e.parent_id == ^employment_id,
      where: e.start_time <= ^at_time,
      where: is_nil(e.end_time) or e.end_time > ^at_time,
      where: e.status == "active",
      order_by: [desc: e.start_time],
      limit: 1
    )
    |> Repo.one()
  end
end
```

### Usage Example

```elixir
# ✅ Create employment first (using Employments context)
{:ok, {employment, _}} = Mosaic.Employments.create_employment(worker.id, %{
  "start_time" => ~U[2024-01-01 00:00:00Z],
  "role" => "Warehouse Associate",
  "contract_type" => "full_time"
})

# ✅ Add compensation rate using Employments context
{:ok, rate} = Mosaic.Employments.add_compensation_rate(employment.id, %{
  effective_date: ~U[2024-01-01 00:00:00Z],
  base_rate: 18.50,
  rate_unit: "hour",
  currency: "USD"
})

# Query current rate
current_rate = Mosaic.Employments.get_active_rate(employment.id)
```

---

## Summary of Domain Contexts

### Always Use These Contexts From Application Code

| Domain | Context Module | Use For |
|--------|---------------|---------|
| Workers | `Mosaic.Workers` | Create/query/update workers |
| Locations | `Mosaic.Locations` | Create/query/update locations |
| Employments | `Mosaic.Employments` | Create/query/update employments |
| Shifts | `Mosaic.Shifts` | Create/query/update shifts |
| Schedules | `Mosaic.Schedules` | Create/query/update schedules |
| Timekeeping | `Mosaic.Timekeeping` | Clock events, time periods |
| Payroll | `Mosaic.Payroll` | Payroll pieces |

### Never Call These Directly

- ❌ `Events.create_event(...)` - Use domain contexts
- ❌ `Entities.create_entity(...)` - Use Workers, Locations, etc.

### Core Contexts Are Used Internally

Domain contexts use `Events` and `Entities` internally to:
- Look up event types
- Create events with proper validation
- Query across domains

---

## Testing Strategy

```elixir
# test/mosaic/schedules_test.exs
defmodule Mosaic.SchedulesTest do
  use Mosaic.DataCase

  describe "create_schedule/2" do
    test "creates schedule with location participation" do
      # ✅ Use Locations context
      {:ok, location} = Mosaic.Locations.create_location(%{
        "properties" => %{"name" => "Building A", "address" => "123 Main"}
      })
      
      # ✅ Use Schedules context
      {:ok, schedule} = Mosaic.Schedules.create_schedule(location.id, %{
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-31 23:59:59Z]
      })
      
      assert schedule.status == "draft"
    end
  end
end

# test/mosaic/timekeeping_test.exs
defmodule Mosaic.TimekeepingTest do
  use Mosaic.DataCase

  describe "clock_in/2 and clock_out/2" do
    test "creates clock events" do
      # ✅ Use Workers context
      {:ok, worker} = Mosaic.Workers.create_worker(%{
        "properties" => %{"name" => "John", "email" => "john@example.com"}
      })
      
      # ✅ Use Timekeeping context
      {:ok, clock_in} = Mosaic.Timekeeping.clock_in(worker.id)
      {:ok, clock_out} = Mosaic.Timekeeping.clock_out(worker.id)
      
      assert clock_in.properties["event_type"] == "in"
      assert clock_out.properties["event_type"] == "out"
    end
  end
end
```

---

## See Also

- [architecture.md](architecture.md) - Why use domain contexts (The Golden Rule)
- [01-events-and-participations.md](01-events-and-participations.md) - Core patterns
- [03-event-types.md](03-event-types.md) - Event type system
- [04-temporal-modeling.md](04-temporal-modeling.md) - Temporal validation
- [10-configuration-strategy.md](10-configuration-strategy.md) - Configuration patterns
