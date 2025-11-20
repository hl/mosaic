# Mosaic Technical Specifications

Mosaic is a workforce management system built on a **temporal event-participation data model** that treats all business operations as time-bound events with associated participants.

## 🎯 START HERE

### **New to Mosaic? Read these first:**

1. **[00-start-here.md](specs/00-start-here.md)** - Quick start guide with examples
2. **[architecture.md](specs/architecture.md)** - The Golden Rule: Always use domain contexts
3. **[index.md](specs/index.md)** - Complete navigation and reference

### The Most Important Rule

**Never access core contexts directly from application code:**

```elixir
# ✅ CORRECT - Use domain contexts
Mosaic.Shifts.create_shift(employment_id, worker_id, attrs)
Mosaic.Workers.create_worker(attrs)
Mosaic.Employments.create_employment(worker_id, attrs)
Mosaic.Locations.create_location(attrs)

# ❌ WRONG - Bypasses business logic
Events.create_event(attrs)
Entities.create_entity(attrs)
```

**Why?** Domain contexts contain validation, business logic, and relationship management. Core contexts are infrastructure.

---

## Architecture Overview

The system is built around three core concepts:

1. **Events** - Time-bounded occurrences with specific types (shifts, employments, breaks, work periods)
2. **Participations** - Relationships between entities and events, defining roles and context
3. **Entities** - The actors in the system (workers, locations, organizations)

This architecture provides flexibility to model complex temporal relationships while maintaining a normalized, queryable data structure.

### The Key Paradigm Shift

**Think in terms of temporal facts, not domain tables.**

Instead of creating separate tables for each domain concept (shifts, contracts, pay_runs), Mosaic models everything as **temporal facts about people and organizations**:

- A shift is not a row in a `shifts` table, but an **event that a worker participates in**
- An employment is not a `contracts` row, but a **temporal relationship between a worker and organization**
- A break is not separate data, but a **nested event within a shift event**

This is the same pattern used by enterprise platforms:
- **Salesforce**: Activities, Tasks, and Events with flexible Who/What relationships
- **Microsoft Dynamics**: Activity entities with Party List attributes
- **SAP**: Business events with participant roles

By treating everything as events with participations, you gain:
- **Flexibility**: New event types without schema changes
- **Auditability**: Complete temporal history
- **Queryability**: Uniform patterns across all time-bound operations
- **Scalability**: Add complexity without restructuring
- **Temporal Intelligence**: Query state at any point in time

The power lies in abstracting away domain-specific tables and embracing **events as first-class citizens**.

---

## Specification Index

### 🔴 Critical Reading (Start Here)

- **[00-start-here.md](specs/00-start-here.md)** - Quick start guide with practical examples
- **[architecture.md](specs/architecture.md)** - The Golden Rule and layered architecture
- **[index.md](specs/index.md)** - Complete index with quick reference

### Core Data Model

- **[01-events-and-participations.md](specs/01-events-and-participations.md)** - The foundational event-participation model
  - Event-participation pattern
  - Database schema
  - Event hierarchy
  - Query patterns
  - Domain contexts vs core infrastructure

- **[02-entities.md](specs/02-entities.md)** - Entity types and their properties
  - Entity schema (domain-agnostic core)
  - Worker and Location wrappers
  - Context modules
  - Validation strategy
  - Adding new entity types

- **[03-event-types.md](specs/03-event-types.md)** - Event type system and behavior pattern
  - Event type registry
  - Protocol-based dispatch
  - Wrapper modules (Shift, Employment)
  - Adding new event types
  - Type-specific properties

- **[04-temporal-modeling.md](specs/04-temporal-modeling.md)** - How time and temporal relationships are handled
  - Time representation
  - Event temporal bounds
  - Hierarchical constraints
  - Overlap detection
  - Duration calculations

### Technical Patterns

- **[08-properties-pattern.md](specs/08-properties-pattern.md)** - JSONB properties and virtual fields
  - Property casting
  - Validation patterns
  - Data flow
  - Query patterns
  - Best practices

### Implementation Guides

- **[09-scheduling-model.md](specs/09-scheduling-model.md)** ⚠️ CRITICAL - Step-by-step implementation
  - Location hierarchy
  - Schedule events
  - Shifts and assignments
  - Work periods and breaks
  - Clock events (timekeeping)
  - Payroll pieces
  - Compensation rates
  - Complete working examples using domain contexts

- **[10-configuration-strategy.md](specs/10-configuration-strategy.md)** - Configuration-driven features
  - Blueprint system for tenant provisioning
  - Jurisdiction-specific configuration
  - Event creation helpers (for internal use)
  - Two-layer architecture patterns
  - Best practices

- **[11-draft-publish-dependencies.md](specs/11-draft-publish-dependencies.md)** 📋 PROPOSED - Draft-publish workflow
  - Problem statement
  - Proposed schema extensions (clearly marked)
  - Implementation with current schema
  - Validation patterns
  - Migration path
  - **Note:** Future features, not current implementation

---

## Key Design Decisions

### Event-Participation Model
Rather than traditional relational tables (e.g., `shifts`, `employments`), all temporal entities are stored as **events** with a polymorphic type system. This provides:
- Unified temporal querying
- Flexible nesting (shifts within employments, breaks within shifts)
- Consistent participation tracking across all event types

### Properties as Extension Points
Event types use JSONB `properties` columns for type-specific data, allowing domain-specific fields without schema migrations while maintaining queryability for common temporal attributes.

### Behaviour-Based Dispatch
Event type implementations use Elixir behaviours for extensibility, allowing new event types to be added by implementing a single behaviour and registering in a central module.

### Two-Layer Architecture

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
│   - Shifts                          │
│   - Workers                         │
│   - Employments                     │
│   - Locations                       │
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
│   Core Infrastructure               │
│   - Events                          │
│   - Entities                        │
│   - Participations                  │
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

## Companies Using Similar Patterns

The event-participation and temporal modeling patterns employed by Mosaic are battle-tested by major technology companies:

### Event Sourcing & Event-Driven Architecture

**Netflix**
- Processes over 1 billion events daily
- Uses Cassandra-backed event sourcing for their download feature
- Every user interaction generates events consumed by multiple services
- Improved flexibility, reliability, scalability, and debuggability

**Uber**
- Manages millions of rides daily with event-driven architecture
- Real-time traffic data from telemetry events powers routing optimization
- Ride requests generate events consumed by matching, pricing, and ETA services

**Amazon**
- Uses CQRS + Event Sourcing for shopping cart systems
- Event-driven architecture enables scalability across services

**Stripe**
- Employs temporal workflows for Stripe Capital and Billing
- Maintains bi-temporal data for financial transactions and auditing

**Airbnb**
- Event sourcing for booking and reservation management
- Temporal data tracking for pricing and availability

### Enterprise Platforms (Activity-Based Models)

**Salesforce**
- Core data model based on Activities, Tasks, and Events
- Flexible Who/What (WhoId/WhatId) relationships for participation
- Everything is an activity that people/organizations participate in
- Powers one of the world's largest SaaS platforms

**Microsoft Dynamics**
- Activity entities with Party List attributes
- Flexible participation in activities across all entities
- Event-driven workflows and business processes

**SAP**
- Business events with participant roles
- Event-based integration across modules
- Temporal tracking for business transactions

### Temporal & Bi-Temporal Databases

**Financial Services Industry**
- Leading users of bi-temporal capabilities
- Track both valid time (when event occurred) and transaction time (when recorded)
- Enables regulatory compliance, auditing, and risk management
- Maintains complete history for reconstruction at any point

**Healthcare Systems**
- Patient history tracking with temporal databases
- Maintaining treatment timelines and medication histories
- Regulatory compliance for medical records

**IBM & Enterprise Systems**
- IBM Db2 Event Store for event sourcing with Kafka integration
- Optimization for downstream analytical processing
- Used in microservices architectures

### Why This Pattern Works at Scale

1. **Auditability**: Complete history of all changes
2. **Temporal Queries**: Query state at any point in time
3. **Debugging**: Replay events to reproduce issues
4. **Compliance**: Meet regulatory requirements for data retention
5. **Scalability**: Event streams handle high throughput
6. **Flexibility**: Add new event types without schema changes

Mosaic applies these proven patterns specifically to workforce management, where temporal tracking of employments, shifts, and work periods is critical for compliance, payroll, and operational efficiency.

---

## Technology Stack

- **Phoenix Framework 1.8** - Web framework
- **Phoenix LiveView 1.1** - Real-time UI
- **Ecto 3.13** - Database layer with PostgreSQL
- **PostgreSQL** - Primary datastore with JSONB support

---

## Quick Reference

### Common Operations

```elixir
# Creating a worker
{:ok, worker} = Mosaic.Workers.create_worker(%{
  "properties" => %{
    "name" => "John Doe",
    "email" => "john@example.com"
  }
})

# Creating an employment
{:ok, {employment, participation}} = Mosaic.Employments.create_employment(
  worker.id,
  %{
    "start_time" => ~U[2024-01-01 00:00:00Z],
    "role" => "Warehouse Associate"
  }
)

# Creating a shift
{:ok, {shift, participation}} = Mosaic.Shifts.create_shift(
  employment.id,
  worker.id,
  %{
    "start_time" => ~U[2024-01-15 09:00:00Z],
    "end_time" => ~U[2024-01-15 17:00:00Z],
    "location" => "Building A"
  }
)

# Querying shifts
shifts = Mosaic.Shifts.list_shifts_for_worker(worker.id)
```

### Access Patterns by Domain

| What You Need | Context to Use | Never Use |
|--------------|----------------|-----------|
| Create/query shifts | `Mosaic.Shifts` | `Events.create_event` |
| Create/query workers | `Mosaic.Workers` | `Entities.create_entity` |
| Create/query employments | `Mosaic.Employments` | `Events.create_event` |
| Create/query locations | `Mosaic.Locations` | `Entities.create_entity` |

---

## Getting Started

1. **Read [00-start-here.md](specs/00-start-here.md)** for quick examples
2. **Read [architecture.md](specs/architecture.md)** to understand the Golden Rule
3. **Review [index.md](specs/index.md)** for complete navigation
4. **Study core concepts** (specs 01-04) to understand the data model
5. **Follow implementation guides** (specs 09-11) when building features

---

## Common Mistakes to Avoid

❌ **DON'T** call `Events.create_event()` from controllers
✅ **DO** call `Shifts.create_shift()` from controllers

❌ **DON'T** query `Event` directly from LiveViews
✅ **DO** call `Shifts.list_shifts_for_worker()` from LiveViews

❌ **DON'T** call `Entities.create_entity()` from background jobs
✅ **DO** call `Workers.create_worker()` from background jobs

**Why?** Domain contexts include validation, business logic, and ensure data consistency. Core contexts are just infrastructure.

---

## Documentation Status

- **00-start-here.md** - ✅ Quick start guide
- **architecture.md** - ✅ Architecture explanation
- **index.md** - ✅ Complete navigation
- **01-events-and-participations.md** - ✅ Updated and accurate
- **02-entities.md** - ✅ Updated and accurate
- **03-event-types.md** - ✅ Updated and accurate
- **04-temporal-modeling.md** - ✅ Accurate
- **08-properties-pattern.md** - ✅ Accurate
- **09-scheduling-model.md** - ✅ Fully updated with correct patterns
- **10-configuration-strategy.md** - ✅ Fully updated with correct patterns
- **11-draft-publish-dependencies.md** - ✅ Fully updated (proposed features)

For detailed information about each subsystem, refer to the individual specification documents.
