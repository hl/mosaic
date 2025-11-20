# Event Types

> **Navigation:** [📚 Index](index.md) | [🎯 Start Here](00-start-here.md) | [🔴 Architecture](architecture.md)

## Overview

Event types define the polymorphic behavior system that allows different kinds of events to have custom validation, business logic, and properties while sharing a common data structure.

**IMPORTANT:** The core `Event` schema (`Mosaic.Events.Event`) is completely **domain-agnostic**. It has zero knowledge of specific event types like shifts, employments, or breaks. Domain-specific logic lives in **wrapper modules** that build on top of the generic Event schema.

## Database Schema

```sql
CREATE TABLE event_types (
  id UUID PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  category VARCHAR(100),
  can_nest BOOLEAN DEFAULT false,
  can_have_children BOOLEAN DEFAULT false,
  requires_participation BOOLEAN DEFAULT true,
  schema JSONB DEFAULT '{}',
  rules JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  inserted_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);
```

## Event Type Registry

Current event types in the system:

### Employment
- **Category:** Workforce
- **Can Nest:** false (top-level event)
- **Can Have Children:** true (can contain shifts)
- **Requires Participation:** true
- **Duration:** Long-term (months/years)

### Shift
- **Category:** Scheduling
- **Can Nest:** true (belongs to employment)
- **Can Have Children:** true (contains work periods and breaks)
- **Requires Participation:** true
- **Duration:** Short-term (hours/day)

### Work Period
- **Category:** Time Tracking
- **Can Nest:** true (belongs to shift)
- **Can Have Children:** false
- **Requires Participation:** true
- **Duration:** Minutes/hours

### Break
- **Category:** Time Tracking
- **Can Nest:** true (belongs to shift)
- **Can Have Children:** false
- **Requires Participation:** true
- **Duration:** Minutes
- **Special:** Has `is_paid` property

## Core Event Schema

The `Mosaic.Events.Event` schema is intentionally minimal and domain-agnostic:

**Location:** `/mnt/project/event.ex`

```elixir
defmodule Mosaic.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mosaic.Events.EventType
  alias Mosaic.Participations.Participation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "events" do
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :status, :string, default: "draft"
    field :properties, :map, default: %{}

    belongs_to :event_type, EventType
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :participations, Participation

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(draft active completed cancelled)

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type_id, :parent_id, :start_time, :end_time, :status, :properties])
    |> validate_required([:event_type_id, :start_time])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_time_range()
    |> foreign_key_constraint(:event_type_id)
    |> foreign_key_constraint(:parent_id)
  end

  defp validate_time_range(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && DateTime.compare(end_time, start_time) != :gt do
      add_error(changeset, :end_time, "must be after start time")
    else
      changeset
    end
  end
end
```

**Key Points:**
- No knowledge of shifts, employments, or any specific event type
- Only validates generic temporal and status rules
- Domain-specific validation happens in wrapper modules

## Protocol Pattern

Event types implement custom logic through the `Mosaic.Events.EventTypeBehaviour` protocol. This allows the system to dispatch to type-specific implementations without maintaining a registry of modules.

**Location:** `/mnt/project/event_type_behaviour.ex`

```elixir
defprotocol Mosaic.Events.EventTypeBehaviour do
  @moduledoc """
  Protocol for event type-specific implementations.
  """

  @spec changeset(t(), Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(event_type, event, attrs)
end

defimpl Mosaic.Events.EventTypeBehaviour, for: Mosaic.Events.EventType do
  @moduledoc """
  Protocol implementation that dispatches to event type-specific modules based on name.
  """

  alias Mosaic.Events.Event

  def changeset(%Mosaic.Events.EventType{name: "shift"}, event, attrs) do
    Mosaic.Shifts.Shift.changeset(event, attrs)
  end

  def changeset(%Mosaic.Events.EventType{name: "employment"}, event, attrs) do
    Mosaic.Employments.Employment.changeset(event, attrs)
  end

  # Fallback for event types without custom implementations
  def changeset(%Mosaic.Events.EventType{}, event, attrs) do
    Event.changeset(event, attrs)
  end
end
```

**This protocol-based wrapper pattern:**
- Keeps core Event schema domain-agnostic
- Dispatches to domain-specific wrappers (Shift, Employment)
- Falls back to generic validation when no wrapper exists
- Pattern matches on EventType.name to determine wrapper

### Implementing a New Event Type

To add a new event type (e.g., Time Off), follow these steps:

**Step 1: Create wrapper module** (`lib/mosaic/time_off/time_off_event.ex`):

```elixir
defmodule Mosaic.TimeOff.TimeOffEvent do
  @moduledoc """
  Time off event type wrapper - adds time off-specific validation to Event.
  """

  import Ecto.Changeset
  import Mosaic.ChangesetHelpers
  alias Mosaic.Events.Event

  @property_fields [:reason, :approval_status, :approver_id]

  def changeset(event, attrs) do
    event
    |> Event.changeset(attrs)  # Use core schema first
    |> cast_properties(attrs, @property_fields)  # Add domain properties
    |> validate_time_off_rules()  # Add domain validation
  end

  defp validate_time_off_rules(changeset) do
    case changeset.action do
      nil -> changeset
      _ ->
        properties = get_field(changeset, :properties) || %{}
        
        changeset
        |> validate_property_presence(properties, "reason", "Reason is required")
    end
  end
end
```

**Step 2: Add protocol implementation**

Add pattern match clause in `/mnt/project/event_type_behaviour.ex`:

```elixir
defimpl Mosaic.Events.EventTypeBehaviour, for: Mosaic.Events.EventType do
  # ... existing implementations ...

  def changeset(%Mosaic.Events.EventType{name: "time_off"}, event, attrs) do
    Mosaic.TimeOff.TimeOffEvent.changeset(event, attrs)
  end
end
```

**Step 3: Create context module** (`lib/mosaic/time_off.ex`):

```elixir
defmodule Mosaic.TimeOff do
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Events

  def list_time_off_requests do
    Events.list_events_by_type("time_off",
      preload: [:event_type, participations: :participant]
    )
  end

  def create_time_off_request(worker_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name("time_off"),
           attrs <- Map.put(attrs, "event_type_id", event_type.id),
           {:ok, event} <- Events.create_event(attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "requestor"
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
end
```

**Step 4: Seed the database**

Add to seeds file:

```elixir
Repo.insert!(%Mosaic.Events.EventType{
  name: "time_off",
  category: "absence",
  can_nest: false,
  can_have_children: false,
  requires_participation: true
})
```

**Step 5: No changes needed to core Event schema** - It remains domain-agnostic

## Type-Specific Properties

Each event type defines which properties it supports via `@property_fields`:

### Employment Properties
**Location:** `/mnt/project/employment.ex`
- `role` - Job role/title
- `contract_type` - Type of employment contract
- `salary` - Compensation amount

### Shift Properties
**Location:** `/mnt/project/shift.ex`
- `location` - Where the shift takes place
- `department` - Department/team assignment
- `notes` - Additional shift notes

### Break Properties
- `is_paid` - Whether break is paid or unpaid

## Validation Strategy

Event types handle two levels of validation:

### 1. Base Event Validation
Handled by `Mosaic.Events.Event.changeset/2`:
- `event_type_id` required
- `start_time` required
- `end_time` must be after `start_time` (if provided)
- `status` must be valid

### 2. Type-Specific Validation
Handled by event type wrapper modules:
- Required properties (e.g., location for shifts)
- Property format validation
- Business rule validation
- Cross-field validation

## Dispatch Mechanism

The `Mosaic.Events` context dispatches to type-specific changesets using the protocol:

**Location:** `/mnt/project/events.ex`

```elixir
defmodule Mosaic.Events do
  # ... other functions ...

  def create_event(attrs \\ %{}) do
    %Event{}
    |> get_changeset_for_event_type(attrs)
    |> Repo.insert()
  end

  def update_event(%Event{} = event, attrs) do
    event
    |> get_changeset_for_event_type(attrs)
    |> Repo.update()
  end

  # Gets the appropriate changeset based on event type
  defp get_changeset_for_event_type(%Event{} = event, attrs) do
    event_type_id =
      Map.get(attrs, :event_type_id) || Map.get(attrs, "event_type_id") || event.event_type_id

    case event_type_id do
      nil ->
        Event.changeset(event, attrs)

      id ->
        case Repo.get(EventType, id) do
          %EventType{} = event_type ->
            Mosaic.Events.EventTypeBehaviour.changeset(event_type, event, attrs)

          nil ->
            Event.changeset(event, attrs)
        end
    end
  end
end
```

This protocol-based approach ensures:
- Type-specific logic is applied at create/update time
- Pattern matching on `EventType.name` in protocol implementation
- Generic events fall back to base validation
- No manual registry maintenance - just add a new pattern match clause
- Compile-time safety with protocol dispatch

## Context Modules

Each major event type has a context module:

- `Mosaic.Events` (at `/mnt/project/events.ex`) - Generic event operations
- `Mosaic.Employments` (at `/mnt/project/employments.ex`) - Employment management
- `Mosaic.Shifts` (at `/mnt/project/shifts.ex`) - Shift scheduling
- Future: `Mosaic.TimeOff`, `Mosaic.Trainings`, etc.

Context modules provide:
- High-level business operations
- Type-specific queries
- Validation wrappers
- Transaction handling

## Schema vs. Properties

### When to use Event fields
- Common across all/most event types
- Need to index or query efficiently
- Part of core temporal model
- Examples: `start_time`, `end_time`, `status`

### When to use Properties
- Type-specific data
- Flexible/evolving requirements
- Metadata that doesn't need complex queries
- Examples: `location`, `notes`, `approval_status`

## Benefits

### Extensibility
New event types are added without:
- Schema migrations for core tables
- Modifying core Events module dispatch logic
- Breaking existing types
- Maintaining a separate registry module

### Maintainability
- Type logic is isolated in dedicated modules
- Protocol ensures consistent interface across all types
- Pattern matching makes dispatch logic explicit
- Adding new types requires only:
  1. Creating the event type wrapper module
  2. Adding one pattern match clause to the protocol implementation
  3. Seeding the database

### Performance
- Properties indexed with GIN for JSONB queries
- Protocol dispatch is optimized by the BEAM VM
- Event type lookup happens once per operation
- No polymorphic query penalties
- Pattern matching is resolved at compile time

## Architecture Summary

The event type system follows a strict **domain-agnostic core with wrapper pattern**:

```
┌─────────────────────────────────────────────────────┐
│              DOMAIN LAYER                            │
│  (Event Type Wrappers)                              │
├─────────────────────────────────────────────────────┤
│  • Mosaic.Shifts.Shift                              │
│  • Mosaic.Employments.Employment                    │
│  • Mosaic.TimeOff.TimeOffEvent                      │
│  • (Future event types...)                          │
│                                                      │
│  Each wrapper:                                      │
│  1. Calls Event.changeset(event, attrs)             │
│  2. Adds domain-specific property casting           │
│  3. Adds domain-specific validation                 │
└────────────────┬────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────────┐
│              PROTOCOL LAYER                          │
│  (Dispatch to Wrappers)                             │
├─────────────────────────────────────────────────────┤
│  Mosaic.Events.EventTypeBehaviour                   │
│  • Pattern matches on EventType.name                │
│  • Dispatches to appropriate wrapper                │
│  • Falls back to generic Event.changeset/2          │
└────────────────┬────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────────┐
│              CORE LAYER                              │
│  (Domain-Agnostic Event Schema)                     │
├─────────────────────────────────────────────────────┤
│  Mosaic.Events.Event                                │
│  • Temporal fields (start_time, end_time)           │
│  • Status field (draft, active, completed, etc.)    │
│  • Generic properties (JSONB)                       │
│  • NO knowledge of shifts, employments, etc.        │
└─────────────────────────────────────────────────────┘
```

**Key Benefits:**
- **Zero domain knowledge in core** - Event schema never changes for new types
- **Protocol dispatch** - No manual registry maintenance
- **Wrapper pattern** - Domain logic isolated in dedicated modules
- **Extensible** - Add new event types without modifying core schemas

## See Also

- [01-events-and-participations.md](01-events-and-participations.md) - Core event model
- [02-entities.md](02-entities.md) - Entity wrapper pattern (parallel to event wrappers)
- [08-properties-pattern.md](08-properties-pattern.md) - Detailed properties implementation
- [04-temporal-modeling.md](04-temporal-modeling.md) - Temporal validation patterns
