# Event Types

## Overview

Event types define the polymorphic behavior system that allows different kinds of events to have custom validation, business logic, and properties while sharing a common data structure.

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

## Behaviour Pattern

Event types implement custom logic through the `Mosaic.EventTypeBehaviour`:

```elixir
defmodule Mosaic.EventTypeBehaviour do
  @callback changeset(event :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()

  def module_for_name("shift"), do: Mosaic.EventTypes.Shift
  def module_for_name("employment"), do: Mosaic.EventTypes.Employment
  def module_for_name("work_period"), do: nil
  def module_for_name("break"), do: nil
  def module_for_name(_), do: nil
end
```

### Implementing a New Event Type

**Step 1: Create the module**

```elixir
defmodule Mosaic.EventTypes.TimeOff do
  @behaviour Mosaic.EventTypeBehaviour

  import Ecto.Changeset
  alias Mosaic.Event

  @property_fields [:reason, :approval_status, :approver_id]

  def changeset(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> cast_properties(attrs)
    |> validate_time_off_rules()
  end

  defp cast_properties(changeset, attrs) do
    properties = get_field(changeset, :properties, %{})

    updated_properties =
      Enum.reduce(@property_fields, properties, fn field, acc ->
        field_str = to_string(field)
        case Map.get(attrs, field) || Map.get(attrs, field_str) do
          nil -> acc
          value -> Map.put(acc, field_str, value)
        end
      end)

    put_change(changeset, :properties, updated_properties)
  end

  defp validate_time_off_rules(changeset) do
    # Custom validation logic
    changeset
  end
end
```

**Step 2: Register in behaviour module**

```elixir
def module_for_name("time_off"), do: Mosaic.EventTypes.TimeOff
```

**Step 3: Seed the database**

```elixir
Repo.insert!(%EventType{
  name: "time_off",
  category: "absence",
  can_nest: true,
  can_have_children: false,
  requires_participation: true
})
```

## Type-Specific Properties

Each event type defines which properties it supports via `@property_fields`:

### Employment Properties
- `contract_type` - Type of employment contract
- `salary` - Compensation amount

### Shift Properties
- `location` - Where the shift takes place
- `department` - Department/team assignment
- `notes` - Additional shift notes

### Break Properties
- `is_paid` - Whether break is paid or unpaid

## Validation Strategy

Event types handle two levels of validation:

### 1. Base Event Validation
Handled by `Mosaic.Event.changeset/2`:
- `event_type_id` required
- `start_time` required
- `end_time` must be after `start_time` (if provided)
- `status` must be valid

### 2. Type-Specific Validation
Handled by event type modules:
- Required properties (e.g., location for shifts)
- Property format validation
- Business rule validation
- Cross-field validation

## Dispatch Mechanism

The `Mosaic.Events` module dispatches to type-specific changesets:

```elixir
defp get_changeset_for_event_type(%Event{} = event, attrs) do
  event_type_id =
    Map.get(attrs, :event_type_id) ||
    Map.get(attrs, "event_type_id") ||
    event.event_type_id

  with event_type_id when not is_nil(event_type_id) <- event_type_id,
       %EventType{name: name} <- Repo.get(EventType, event_type_id),
       module when not is_nil(module) <-
         Mosaic.EventTypeBehaviour.module_for_name(name) do
    module.changeset(event, attrs)
  else
    _ -> Event.changeset(event, attrs)
  end
end
```

This ensures:
- Type-specific logic is applied at create/update time
- Generic events fall back to base validation
- No hardcoded case statements that grow with each type

## Context Modules

Each major event type has a context module:

- `Mosaic.Employments` - Employment management
- `Mosaic.Shifts` - Shift scheduling
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
- Schema migrations
- Modifying core Events module
- Breaking existing types

### Maintainability
- Type logic is isolated in modules
- Behaviour ensures consistent interface
- Registry makes types discoverable

### Performance
- Properties indexed with GIN for JSONB queries
- Event type dispatch happens once per operation
- No polymorphic query penalties

## See Also

- [01-events-and-participations.md](01-events-and-participations.md) - Core event model
- [08-properties-pattern.md](08-properties-pattern.md) - Detailed properties implementation
- [05-employments.md](05-employments.md) - Employment event type
- [06-shifts.md](06-shifts.md) - Shift event type
