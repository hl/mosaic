# Entities

## Overview

Entities represent the actors and objects in the system that can participate in events. The entity model uses a polymorphic approach with type-specific properties stored as JSONB.

## Database Schema

```sql
CREATE TABLE entities (
  id UUID PRIMARY KEY,
  entity_type VARCHAR(50) NOT NULL,
  properties JSONB DEFAULT '{}',
  inserted_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_entities_entity_type ON entities(entity_type);
CREATE INDEX idx_entities_properties ON entities USING GIN(properties);
```

## Entity Types

### Worker
The primary entity type representing people who perform work.

**Properties:**
- `name` (string) - Full name
- `email` (string) - Contact email
- `phone` (string) - Contact phone number
- Additional fields as needed (address, emergency contact, etc.)

**Usage:**
- Participates in employments as "employee"
- Participates in shifts as "worker"
- Participates in work periods and breaks as "worker"

**Example:**
```elixir
%Entity{
  entity_type: "worker",
  properties: %{
    "name" => "John Doe",
    "email" => "john@example.com",
    "phone" => "555-0123"
  }
}
```

### Future Entity Types

The system is designed to support additional entity types:

**Location**
- Physical work locations
- Properties: address, capacity, facilities
- Participates in shifts as "location"

**Organization**
- Companies, departments, clients
- Properties: name, type, contact info
- Participates in employments as "employer"

**Equipment**
- Tools, vehicles, machinery
- Properties: serial_number, type, status
- Participates in events as "equipment"

**Project**
- Work projects or initiatives
- Properties: name, code, budget
- Participates in shifts as "project"

## Data Access Patterns

### Finding Entities by Type
```elixir
from e in Entity,
  where: e.entity_type == "worker"
```

### Querying Properties
```elixir
from e in Entity,
  where: e.entity_type == "worker",
  where: fragment("?->>'name' ILIKE ?", e.properties, ^"%#{name}%")
```

### Getting Entity with Participations
```elixir
from e in Entity,
  where: e.id == ^id,
  preload: [:participations]
```

## Validation Strategy

### Required Fields per Type

Validation is type-specific and enforced in changesets:

**Worker:**
- `name` required
- `email` optional but must be valid email format if provided
- `phone` optional

### Property Validation

Properties are validated using Ecto embedded schemas or custom validators:

```elixir
defmodule Mosaic.EntityTypes.Worker do
  def changeset(entity, attrs) do
    properties = get_field(changeset, :properties, %{})

    # Validate required properties
    if is_nil(properties["name"]) or properties["name"] == "" do
      add_error(changeset, :properties, "Name is required", field: "name")
    else
      changeset
    end
  end
end
```

## Relationship to Events

Entities participate in events through the `participations` table:

```
Entity (Worker) --< Participation >-- Event (Employment)
Entity (Worker) --< Participation >-- Event (Shift)
Entity (Worker) --< Participation >-- Event (Work Period)
```

A single entity can have multiple participations across different events, each with its own:
- Role
- Temporal bounds
- Participation-specific properties

## Context Module: Workers

The `Mosaic.Workers` context manages worker entities:

**Functions:**
- `list_workers/0` - Get all workers
- `get_worker!/1` - Get worker by ID
- `create_worker/1` - Create new worker
- `update_worker/2` - Update worker properties
- `delete_worker/1` - Delete worker

**Implementation:** `lib/mosaic/workers.ex`

## Extension Points

### Adding New Entity Types

1. Add entity type validation to `Entity` schema
2. Create context module (e.g., `Mosaic.Locations`)
3. Define property validation in entity type module
4. Create LiveView CRUD interface

### Type-Specific Behavior

Similar to events, entities can have type-specific modules:

```elixir
defmodule Mosaic.EntityTypes.Worker do
  @behaviour Mosaic.EntityTypeBehaviour

  def changeset(entity, attrs) do
    # Worker-specific validation
  end
end
```

## Benefits

### Flexibility
- New entity types without schema migrations
- Type-specific properties via JSONB
- Properties indexed for efficient querying

### Consistency
- Uniform entity storage
- Standardized participation mechanism
- Centralized entity management

### Scalability
- Support for diverse entity types
- Properties can grow independently per type
- GIN indexes support flexible property queries

## See Also

- [01-events-and-participations.md](01-events-and-participations.md) - How entities participate in events
- [07-workers.md](07-workers.md) - Worker-specific implementation details
