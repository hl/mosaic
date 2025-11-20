# Mosaic Specifications - Index

> **Navigation:** [📖 Main SPECS.md](../SPECS.md) | [🎯 Start Here](00-start-here.md) | [🔴 Architecture](architecture.md)

All specification documents, updated to match the actual project structure.

## ⚠️ START HERE - Critical Architecture Rule

### [architecture.md](architecture.md) 🔴 **MUST READ**
**The Golden Rule: NEVER access Events or Entities directly from application code.**

Always use domain contexts:
- ✅ `Mosaic.Shifts` for shifts (NOT `Events.create_event`)
- ✅ `Mosaic.Workers` for workers (NOT `Entities.create_entity`)
- ✅ `Mosaic.Employments` for employments
- ✅ `Mosaic.Locations` for locations

**This document explains WHY and shows correct patterns.**

---

## Core Specifications

### [01-events-and-participations.md](01-events-and-participations.md)
The foundation of Mosaic's data model. Covers:
- Event-participation pattern
- Database schema
- Event hierarchy
- Query patterns
- Domain-agnostic core with wrapper contexts
- **Status:** ✅ Fully updated
- **Note:** Events context is infrastructure - use domain contexts (Shifts, Employments) from app code

### [02-entities.md](02-entities.md)
Entity system and wrapper pattern. Covers:
- Entity schema (domain-agnostic core)
- Worker and Location wrappers
- Context modules
- Validation strategy
- Adding new entity types
- **Status:** ✅ Fully updated
- **Note:** Entities context is infrastructure - use domain contexts (Workers, Locations) from app code

### [03-event-types.md](03-event-types.md)
Event type system and protocol dispatch. Covers:
- Event type registry
- Protocol-based dispatch
- Wrapper modules (Shift, Employment)
- Adding new event types
- Type-specific properties
- **Status:** ✅ Fully updated

### [04-temporal-modeling.md](04-temporal-modeling.md)
Temporal constraints and validation. Covers:
- Time representation
- Event temporal bounds
- Hierarchical constraints
- Overlap detection
- Duration calculations
- **Status:** ✅ Already accurate

### [08-properties-pattern.md](08-properties-pattern.md)
JSONB properties usage. Covers:
- Property casting
- Validation patterns
- Data flow
- Query patterns
- Best practices
- **Status:** ✅ Already accurate

## Implementation Guides

### [09-scheduling-model.md](09-scheduling-model.md) ⚠️ CRITICAL
Step-by-step implementation guide. Covers:
- Location hierarchy
- Schedule events
- Shifts and assignments
- Work periods and breaks
- Clock events (timekeeping)
- Payroll pieces
- **Status:** ✅ Major updates - all examples fixed
- **Critical Changes:** 
  - Fixed event creation patterns
  - Corrected all queries
  - Proper participation creation
  - Transaction wrapping
  - **Uses domain contexts correctly**

### [10-configuration-strategy.md](10-configuration-strategy.md)
Configuration-driven features. Covers:
- Blueprint system for tenants
- Jurisdiction-specific config
- Event creation helpers
- Best practices
- **Status:** ✅ Major revisions - simplified and corrected
- **Changes:**
  - Removed complexity
  - Added working helper functions
  - Fixed all event creation examples

### [11-draft-publish-dependencies.md](11-draft-publish-dependencies.md) ⚠️ PROPOSED
Draft-publish workflow guide. Covers:
- Problem statement
- Proposed schema extensions (clearly marked)
- Implementation with current schema
- Validation patterns
- Migration path
- **Status:** ✅ Completely rewritten
- **Important:** Clearly distinguishes proposed vs actual schema

## Supporting Documents

### [architecture.md](architecture.md) 🔴 **CRITICAL**
**Must-read document explaining the layered architecture.**
- Why you must use domain contexts
- Wrong vs right patterns
- When core contexts are used
- Decision tree for choosing contexts

## Quick Reference

### The Golden Rule
```
Application Code → Domain Contexts → Core Infrastructure

✅ Mosaic.Shifts.create_shift(...)
❌ Events.create_event(...)

✅ Mosaic.Workers.create_worker(...)
❌ Entities.create_entity(...)
```

### Event Creation (via Domain Context)
```elixir
# From application code, call domain context
Mosaic.Shifts.create_shift(employment_id, worker_id, %{
  "start_time" => start_time,
  "end_time" => end_time,
  "location" => "Building A"
})

# Domain context internally uses Events
# (This happens inside Mosaic.Shifts, not in your app code)
with {:ok, event_type} <- Events.get_event_type_by_name("shift"),
     attrs <- Map.put(attrs, "event_type_id", event_type.id),
     {:ok, event} <- Events.create_event(attrs) do
  # ...
end
```

### Query Pattern (via Domain Context)
```elixir
# From application code, call domain context
Mosaic.Shifts.list_shifts_for_worker(worker_id)

# NOT this (bypasses business logic)
from e in Event,
  join: et in EventType, on: e.event_type_id == et.id,
  where: et.name == "shift"
```

### Domain Context Responsibilities
- Business logic
- Validation
- Authorization
- Transactions
- Relationship management
- Overlap prevention

### Core Context Responsibilities (Internal Use Only)
- Generic CRUD
- Protocol dispatch
- Database operations
- Cross-domain utilities

## File Locations

All actual project files are at `/mnt/project/`:

**Core Infrastructure (used by domain contexts):**
- `event.ex`, `event_type.ex`, `event_type_behaviour.ex`
- `entity.ex`, `participation.ex`
- `events.ex`, `entities.ex`, `participations.ex` (contexts)

**Wrappers (validation, used by domain contexts):**
- `employment.ex`, `shift.ex`
- `worker.ex`, `location.ex`
- `changeset_helpers.ex`

**Domain Contexts (PUBLIC API for app code):**
- `employments.ex`, `shifts.ex`
- `workers.ex`, `locations.ex`

## Access Patterns

### From Your Application Code

```elixir
# ✅ DO - Use domain contexts
Mosaic.Shifts.create_shift(...)
Mosaic.Shifts.list_shifts_for_worker(...)
Mosaic.Workers.create_worker(...)
Mosaic.Employments.create_employment(...)
Mosaic.Locations.create_location(...)

# ❌ DON'T - Skip domain layer
Events.create_event(...)
Entities.create_entity(...)
```

### Inside Domain Contexts

```elixir
defmodule Mosaic.Shifts do
  # ✅ CAN use core contexts internally
  def create_shift(...) do
    Events.create_event(...)  # OK here
    Events.get_event_type_by_name(...)  # OK here
  end
end
```

## Reading Order

1. **🔴 MUST READ FIRST:** [architecture.md](architecture.md)
2. **New to the project?** Then read 01, 02, 03
3. **Implementing features?** Read 09 for patterns
4. **Adding configuration?** See 10
5. **Planning releases?** File 11 shows the direction

## Status Legend

- 🔴 **MUST READ** - Critical architectural concept
- ✅ **Fully updated** - All examples match actual code
- ⚠️ **Critical** - Contains patterns essential to follow
- 📋 **Proposed** - Future features, not current implementation

## Common Mistakes to Avoid

❌ **Calling Events.create_event from a controller**
```elixir
# WRONG
def create(conn, params) do
  Events.create_event(params)  # Bypasses validation!
end
```

✅ **Calling domain context from controller**
```elixir
# RIGHT
def create(conn, params) do
  Shifts.create_shift(employment_id, worker_id, params)
end
```

❌ **Querying events directly**
```elixir
# WRONG - Missing business logic
from e in Event, where: ...
```

✅ **Using domain context query functions**
```elixir
# RIGHT - Includes business logic
Shifts.list_shifts_for_worker(worker_id)
```

❌ **Creating entities directly**
```elixir
# WRONG
Entities.create_entity(%{"entity_type" => "person"})
```

✅ **Using domain context**
```elixir
# RIGHT
Workers.create_worker(%{"properties" => %{...}})
```
