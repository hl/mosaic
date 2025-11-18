# Mosaic Technical Specifications

Mosaic is a workforce management system built on a **temporal event-participation data model** that treats all business operations as time-bound events with associated participants.

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

## Specification Index

### Core Data Model
- [01-events-and-participations.md](specs/01-events-and-participations.md) - The foundational event-participation model
- [02-entities.md](specs/02-entities.md) - Entity types and their properties
- [03-event-types.md](specs/03-event-types.md) - Event type system and behavior pattern
- [04-temporal-modeling.md](specs/04-temporal-modeling.md) - How time and temporal relationships are handled

### Domain Contexts
- [05-employments.md](specs/05-employments.md) - Employment period management
- [06-shifts.md](specs/06-shifts.md) - Shift scheduling and work period tracking
- [07-workers.md](specs/07-workers.md) - Worker entity management

### Technical Implementation
- [08-properties-pattern.md](specs/08-properties-pattern.md) - JSONB properties and virtual fields
- [09-validation-strategy.md](specs/09-validation-strategy.md) - Validation approach across contexts
- [10-liveview-architecture.md](specs/10-liveview-architecture.md) - Phoenix LiveView patterns used

### Data Integrity
- [11-overlap-prevention.md](specs/11-overlap-prevention.md) - Preventing temporal overlaps
- [12-referential-integrity.md](specs/12-referential-integrity.md) - Foreign keys and constraints

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

## Technology Stack

- **Phoenix Framework 1.8** - Web framework
- **Phoenix LiveView 1.1** - Real-time UI
- **Ecto 3.13** - Database layer with PostgreSQL
- **PostgreSQL** - Primary datastore with JSONB support

## Getting Started

Refer to the individual specification documents for detailed information about each subsystem.
