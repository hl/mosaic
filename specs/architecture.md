# Critical Architecture Clarification

> **Navigation:** [📖 Main SPECS.md](../SPECS.md) | [📚 Index](index.md) | [🎯 Start Here](00-start-here.md)

## The Golden Rule: Always Use Domain Contexts

**NEVER access core schemas directly for domain operations. ALWAYS go through the domain-specific context.**

## Wrong vs Right Patterns

### ❌ WRONG - Bypassing Domain Context

```elixir
# DON'T do this for shifts
Events.create_event(%{
  "event_type_id" => shift_type_id,
  "start_time" => start_time,
  ...
})

# DON'T do this for workers
Entities.create_entity(%{
  "entity_type" => "person",
  "properties" => %{"name" => "John"}
})
```

### ✅ RIGHT - Using Domain Context

```elixir
# DO use the Shifts context for shifts
Mosaic.Shifts.create_shift(employment_id, worker_id, %{
  "start_time" => start_time,
  "end_time" => end_time,
  "location" => "Building A"
})

# DO use the Workers context for workers
Mosaic.Workers.create_worker(%{
  "properties" => %{
    "name" => "John Doe",
    "email" => "john@example.com"
  }
})
```

## The Architecture

```
┌─────────────────────────────────────────────────────┐
│              APPLICATION LAYER                       │
│         (Controllers, LiveViews)                    │
└────────────────┬────────────────────────────────────┘
                 ↓
                 │ ALWAYS call domain contexts
                 ↓
┌─────────────────────────────────────────────────────┐
│           DOMAIN CONTEXTS (PUBLIC API)               │
│                                                      │
│  Mosaic.Shifts           Mosaic.Workers             │
│  Mosaic.Employments      Mosaic.Locations           │
│                                                      │
│  • Business logic        • Validation               │
│  • Transactions          • Authorization            │
│  • Overlap checks        • Relationships            │
└────────────────┬────────────────────────────────────┘
                 ↓
                 │ Domain contexts coordinate:
                 │ - Wrapper modules (validation)
                 │ - Core contexts (persistence)
                 ↓
┌─────────────────────────────────────────────────────┐
│          WRAPPER LAYER (VALIDATION)                  │
│                                                      │
│  Mosaic.Shifts.Shift    Mosaic.Workers.Worker      │
│  Mosaic.Employments.Employment                      │
│                         Mosaic.Locations.Location   │
└────────────────┬────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────────┐
│       CORE CONTEXTS (INFRASTRUCTURE)                 │
│      **NOT CALLED DIRECTLY BY APP CODE**            │
│                                                      │
│  Mosaic.Events          Mosaic.Entities             │
│  Mosaic.Participations                              │
│                                                      │
│  • Generic CRUD         • No business logic         │
│  • Database operations  • Protocol dispatch         │
└─────────────────────────────────────────────────────┘
```

## Wrapper Behaviors and Type Functions

All wrapper modules must implement behaviors that enforce type declaration:

### Event Wrappers

Event wrappers implement `Mosaic.Events.EventWrapper` behavior:

```elixir
defmodule Mosaic.Shifts.Shift do
  @behaviour Mosaic.Events.EventWrapper

  @impl Mosaic.Events.EventWrapper
  def event_type, do: "shift"

  def changeset(event, attrs) do
    # Shift-specific validation
  end
end
```

### Entity Wrappers

Entity wrappers implement `Mosaic.Entities.EntityWrapper` behavior:

```elixir
defmodule Mosaic.Workers.Worker do
  @behaviour Mosaic.Entities.EntityWrapper

  @impl Mosaic.Entities.EntityWrapper
  def entity_type, do: "person"

  def changeset(entity, attrs) do
    # Worker-specific validation
  end
end
```

### Using Type Functions in Contexts

Domain contexts use these type functions instead of hardcoded strings:

```elixir
defmodule Mosaic.Shifts do
  alias Mosaic.Shifts.Shift
  alias Mosaic.Employments.Employment

  def create_shift(employment_id, worker_id, attrs) do
    with {:ok, event_type} <- Events.get_event_type_by_name(Shift.event_type()),
         {:ok, employment} <- Events.validate_event_type(employment_id, Employment.event_type()) do
      # Create shift...
    end
  end

  def list_shifts do
    Events.list_events_by_type(Shift.event_type())
  end

  defp validate_no_overlap(worker_id, attrs) do
    from e in Event,
      join: et in assoc(e, :event_type),
      where: et.name == ^Shift.event_type()
    # ...
  end
end
```

### Why Behaviors Matter

1. **Compile-time enforcement**: Elixir compiler warns if a wrapper doesn't implement `event_type/0` or `entity_type/0`
2. **No magic strings**: Type names are defined once in wrapper modules
3. **Easy refactoring**: Change type name in one place, queries update automatically
4. **Self-documenting**: `Shift.event_type()` is clearer than `"shift"`

## Why This Matters

### 1. Business Logic Encapsulation

```elixir
# ❌ WRONG - Missing business logic
{:ok, shift} = Events.create_event(attrs)
# Missing: overlap validation, employment boundary checks, participation creation

# ✅ RIGHT - All business logic applied
{:ok, {shift, participation}} = Shifts.create_shift(employment_id, worker_id, attrs)
# Includes: validation, overlap checks, participation creation, transaction wrapping
```

### 2. Data Consistency

```elixir
# ❌ WRONG - Creates orphaned event
event = Events.create_event(%{"event_type_id" => shift_type_id, ...})
# No participation created! Who is this shift for?

# ✅ RIGHT - Creates event AND participation
{shift, participation} = Shifts.create_shift(employment_id, worker_id, attrs)
# Atomic transaction ensures consistency
```

### 3. Validation

```elixir
# ❌ WRONG - Bypasses domain validation
Events.create_event(%{
  "event_type_id" => shift_type_id,
  "start_time" => start_time,
  "end_time" => end_time
  # Missing required: location
  # No overlap check
  # No employment boundary check
})

# ✅ RIGHT - Full validation
Shifts.create_shift(employment_id, worker_id, %{
  "start_time" => start_time,
  "end_time" => end_time,
  "location" => "Building A"
  # Validates: location required
  # Checks: no overlaps
  # Validates: within employment bounds
})
```

## Access Patterns by Domain

### Events (Time-bounded occurrences)

| Domain | Context | Purpose |
|--------|---------|---------|
| Shifts | `Mosaic.Shifts` | Create/query/update shifts |
| Employments | `Mosaic.Employments` | Create/query/update employments |
| Schedules | `Mosaic.Schedules` | Create/query/update schedules (future) |
| Time Off | `Mosaic.TimeOff` | Create/query/update time off (future) |

**NEVER use `Mosaic.Events` directly from application code.**

### Entities (Participants)

| Domain | Context | Purpose |
|--------|---------|---------|
| Workers | `Mosaic.Workers` | Create/query/update workers |
| Locations | `Mosaic.Locations` | Create/query/update locations |
| Organizations | `Mosaic.Organizations` | Create/query/update orgs (future) |

**NEVER use `Mosaic.Entities` directly from application code.**

## When to Use Core Contexts

Core contexts (`Events`, `Entities`, `Participations`) are ONLY used:

1. **By domain contexts internally**
   ```elixir
   defmodule Mosaic.Shifts do
     def create_shift(employment_id, worker_id, attrs) do
       # Domain context can call core context
       Events.create_event(attrs)
     end
   end
   ```

2. **For generic cross-domain queries**
   ```elixir
   # Getting event hierarchy (used by multiple domains)
   Events.get_event_hierarchy(event_id)
   
   # Generic event validation (shared utility)
   Events.validate_event_type(event_id, "shift")
   ```

3. **For internal utilities**
   ```elixir
   # Protocol dispatch (internal mechanism)
   Events.get_changeset_for_event_type(event, attrs)
   ```

## Examples from Actual Code

### Creating a Shift

```elixir
# ✅ CORRECT - From shifts.ex context
def create_shift(employment_id, worker_id, attrs \\ %{}) do
  Repo.transaction(fn ->
    with {:ok, employment} <- validate_employment(employment_id),
         :ok <- validate_shift_in_employment(attrs, employment),
         :ok <- validate_no_shift_overlap(worker_id, attrs),
         {:ok, event_type} <- Events.get_event_type_by_name("shift"),
         attrs <- Map.merge(attrs, %{
           "event_type_id" => event_type.id,
           "parent_id" => employment_id
         }),
         {:ok, shift} <- Events.create_event(attrs),  # Core context called internally
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
```

### Creating a Worker

```elixir
# ✅ CORRECT - From workers.ex context
def create_worker(attrs \\ %{}) do
  %Entity{}
  |> Worker.changeset(attrs)  # Wrapper validates
  |> Repo.insert()            # Core operation, but wrapped by context
end
```

### Querying Shifts

```elixir
# ✅ CORRECT - From shifts.ex context
def list_shifts_for_worker(worker_id, opts \\ []) do
  opts = Keyword.merge(opts,
    preload: [:event_type, :parent, :children, participations: :participant]
  )
  
  # Uses Events utility internally
  Events.list_events_for_participant("shift", worker_id, opts)
end
```

## Summary

**The Rule:**
- Application code → Domain contexts (Shifts, Workers, etc.)
- Domain contexts → Core contexts (Events, Entities) + Wrappers
- Core contexts → Database

**Never skip the domain layer!**

This ensures:
- ✅ Business logic is applied
- ✅ Validation occurs
- ✅ Relationships are maintained
- ✅ Transactions are atomic
- ✅ Authorization checks happen
- ✅ Code is maintainable

## Quick Decision Tree

```
Need to work with a shift?
  → Use Mosaic.Shifts

Need to work with a worker?
  → Use Mosaic.Workers

Need to work with an employment?
  → Use Mosaic.Employments

Need to work with a location?
  → Use Mosaic.Locations

Building a new feature that needs generic event queries?
  → Create a new domain context
  → That context can use Events/Entities internally

Never directly use Events or Entities from:
  ❌ Controllers
  ❌ LiveViews
  ❌ Background jobs
  ❌ API handlers
```

---

## See Also

- [00-start-here.md](00-start-here.md) - Quick start guide with practical examples
- [index.md](index.md) - Complete specification index
- [01-events-and-participations.md](01-events-and-participations.md) - Core data model
- [09-scheduling-model.md](09-scheduling-model.md) - Implementation examples following these patterns
