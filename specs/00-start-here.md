# 🎯 START HERE - Mosaic Architecture Overview

> **Navigation:** [📖 Main SPECS.md](../SPECS.md) | [📚 Index](index.md) | [🔴 Architecture](architecture.md)

## The Most Important Rule

### 🔴 ALWAYS Use Domain Contexts

```
✅ Application Code → Domain Contexts (Shifts, Workers, Employments, Locations)
❌ Application Code → Core Contexts (Events, Entities)

Domain contexts contain business logic. Core contexts are infrastructure.
```

**Read this first:** [architecture.md](architecture.md)

---

## Quick Start Guide

### 1. Creating a Worker

```elixir
# ✅ CORRECT
{:ok, worker} = Mosaic.Workers.create_worker(%{
  "properties" => %{
    "name" => "John Doe",
    "email" => "john@example.com",
    "phone" => "555-0123"
  }
})

# ❌ WRONG - Bypasses validation
Mosaic.Entities.create_entity(...)
```

### 2. Creating a Shift

```elixir
# ✅ CORRECT
{:ok, {shift, participation}} = Mosaic.Shifts.create_shift(
  employment_id,
  worker_id,
  %{
    "start_time" => ~U[2024-01-15 09:00:00Z],
    "end_time" => ~U[2024-01-15 17:00:00Z],
    "location" => "Building A",
    "department" => "Logistics"
  }
)

# ❌ WRONG - Missing business logic
Mosaic.Events.create_event(...)
```

### 3. Querying Shifts

```elixir
# ✅ CORRECT
shifts = Mosaic.Shifts.list_shifts_for_worker(worker_id)

# ❌ WRONG - Bypasses business logic
from e in Event, join: et in EventType, ...
```

---

## Architecture Layers

```
┌─────────────────────────────────────┐
│   Application Layer                 │
│   (Controllers, LiveViews)          │
│                                     │
│   ✅ Call: Shifts, Workers,        │
│           Employments, Locations    │
│   ❌ Never: Events, Entities       │
└──────────────┬──────────────────────┘
               │
               ↓
┌─────────────────────────────────────┐
│   Domain Contexts (PUBLIC API)      │
│   /mnt/project/shifts.ex            │
│   /mnt/project/workers.ex           │
│   /mnt/project/employments.ex       │
│   /mnt/project/locations.ex         │
│                                     │
│   Contains:                         │
│   • Business Logic                  │
│   • Validation                      │
│   • Transactions                    │
│   • Overlap Prevention              │
└──────────────┬──────────────────────┘
               │
               ↓
┌─────────────────────────────────────┐
│   Wrapper Layer                     │
│   /mnt/project/shift.ex             │
│   /mnt/project/worker.ex            │
│   /mnt/project/employment.ex        │
│   /mnt/project/location.ex          │
│                                     │
│   Contains:                         │
│   • Type-specific Validation        │
│   • Property Casting                │
└──────────────┬──────────────────────┘
               │
               ↓
┌─────────────────────────────────────┐
│   Core Infrastructure               │
│   /mnt/project/events.ex            │
│   /mnt/project/entities.ex          │
│   /mnt/project/participations.ex    │
│                                     │
│   Contains:                         │
│   • Generic CRUD                    │
│   • Protocol Dispatch               │
│   • Database Operations             │
│                                     │
│   ⚠️  NOT CALLED DIRECTLY BY APP   │
└─────────────────────────────────────┘
```

---

## What You Need to Know

### For Application Development

**You will use these contexts:**
- `Mosaic.Shifts` - All shift operations
- `Mosaic.Employments` - All employment operations
- `Mosaic.Workers` - All worker operations
- `Mosaic.Locations` - All location operations

**You will NOT directly use:**
- `Mosaic.Events` - Infrastructure layer
- `Mosaic.Entities` - Infrastructure layer
- `Mosaic.Participations` - Infrastructure layer

### Why This Matters

#### ❌ Without Domain Context
```elixir
# Missing: validation, overlap checks, participation creation
Events.create_event(%{
  "event_type_id" => shift_type_id,
  "start_time" => start,
  "end_time" => end_time
})
# Result: Data inconsistency, orphaned events, no validation
```

#### ✅ With Domain Context
```elixir
# Includes: validation, overlap checks, participation creation, transactions
Shifts.create_shift(employment_id, worker_id, %{
  "start_time" => start,
  "end_time" => end_time,
  "location" => "Building A"
})
# Result: Validated, consistent, complete data
```

---

## Documentation Map

### 🔴 Critical Reading (Read First)
1. [architecture.md](architecture.md) - **The Golden Rule**
2. [index.md](index.md) - Navigation with quick reference

### 📚 Core Concepts (Read Second)
3. [01-events-and-participations.md](01-events-and-participations.md) - Data model foundation
4. [02-entities.md](02-entities.md) - Entity system
5. [03-event-types.md](03-event-types.md) - Event type system

### 🛠️ Implementation (Read When Building)
6. [09-scheduling-model.md](09-scheduling-model.md) - Scheduling implementation
7. [10-configuration-strategy.md](10-configuration-strategy.md) - Configuration patterns
8. [04-temporal-modeling.md](04-temporal-modeling.md) - Time-based validation
9. [08-properties-pattern.md](08-properties-pattern.md) - JSONB properties

### 📋 Future Planning
10. [11-draft-publish-dependencies.md](11-draft-publish-dependencies.md) - Proposed features

---

## Decision Tree

```
❓ What do I need to do?

├─ Create/update/query a shift
│  └─ Use: Mosaic.Shifts
│
├─ Create/update/query a worker
│  └─ Use: Mosaic.Workers
│
├─ Create/update/query an employment
│  └─ Use: Mosaic.Employments
│
├─ Create/update/query a location
│  └─ Use: Mosaic.Locations
│
├─ Add a new event type (e.g., Time Off)
│  ├─ Create wrapper module (lib/mosaic/time_off/time_off_event.ex)
│  ├─ Add to protocol (event_type_behaviour.ex)
│  ├─ Create context (lib/mosaic/time_off.ex)
│  └─ See: 03-event-types.md
│
└─ Add a new entity type (e.g., Organization)
   ├─ Create wrapper module (lib/mosaic/organizations/organization.ex)
   ├─ Create context (lib/mosaic/organizations.ex)
   └─ See: 02-entities.md
```

---

## Common Patterns

### Creating with Relationships

```elixir
# Employment belongs to no parent
Employments.create_employment(worker_id, %{
  "start_time" => start_date,
  "role" => "Warehouse Associate",
  "contract_type" => "full_time"
})

# Shift belongs to employment
Shifts.create_shift(employment_id, worker_id, %{
  "start_time" => shift_start,
  "end_time" => shift_end,
  "location" => "Warehouse 1"
})
```

### Querying

```elixir
# Get all shifts for a worker
Shifts.list_shifts_for_worker(worker_id)

# Get all employments for a worker
Employments.list_employments_for_worker(worker_id)

# Search workers by name
Workers.search_workers("John")
```

### Validation Happens Automatically

```elixir
# This will fail if:
# - Location is missing
# - Shift overlaps another shift
# - Shift is outside employment bounds
Shifts.create_shift(employment_id, worker_id, %{
  "start_time" => ...,
  "end_time" => ...
  # Missing "location" - will fail validation
})
```

---

## Key Files Reference

### Domain Contexts (Your Entry Points)
- `/mnt/project/shifts.ex` - Shift operations
- `/mnt/project/employments.ex` - Employment operations  
- `/mnt/project/workers.ex` - Worker operations
- `/mnt/project/locations.ex` - Location operations

### Wrappers (Validation)
- `/mnt/project/shift.ex` - Shift validation
- `/mnt/project/employment.ex` - Employment validation
- `/mnt/project/worker.ex` - Worker validation
- `/mnt/project/location.ex` - Location validation

### Core (Infrastructure - Internal Use)
- `/mnt/project/events.ex` - Generic event operations
- `/mnt/project/entities.ex` - Generic entity operations
- `/mnt/project/event.ex` - Event schema
- `/mnt/project/entity.ex` - Entity schema

---

## Next Steps

1. **Read:** [architecture.md](architecture.md)
2. **Understand:** Core concepts (docs 01-03)
3. **Build:** Use domain contexts in your code
4. **Reference:** Implementation guides (docs 09-10) when needed

---

## Questions?

- **"Can I use Events.create_event?"** → No, use domain contexts
- **"Can I query Event directly?"** → No, use domain context query functions
- **"When do I use Events?"** → Only inside domain contexts
- **"How do I add a new event type?"** → See [03-event-types.md](03-event-types.md)
- **"How do I add a new entity type?"** → See [02-entities.md](02-entities.md)

Remember: **Domain contexts are your public API. Core contexts are infrastructure.**
