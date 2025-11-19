# Scheduling & Timekeeping Model

## Purpose
- Capture how location hierarchies, schedules, assignments, and actual timekeeping data map onto Mosaic’s event/participation spine.
- Provide a reference for engineers when extending contexts like `Mosaic.Shifts`, `Mosaic.Locations`, `Mosaic.Participations`, and downstream payroll modules.

## Question 1 — Location hierarchy
> 1 There’s a location hierarchy

- Treat every node (campus, building, floor, room, virtual region) as an `entities` row with `entity_type: "location"` plus descriptive JSONB properties (capacity, timezone, compliance flags).
- Model parent/child relationships as explicit events (e.g., `location_membership`) so hierarchy changes are temporal facts: parent location participates as `parent_location`, child as `child_location`. This keeps history without mutating entity rows.
- When querying “where does this shift live?” traverse from the shift → parent schedule/event → latest active `location_membership` participations to reconstruct the tree at any instant, honoring valid-time semantics from `specs/04-temporal-modeling.md`.

## Question 2 — Schedules linked to hierarchies
> 2 At some point you have schedules linked to those hierarchies

- Define a `schedule` event type that can parent shifts. Its `properties` store recurrence windows, timezone, coverage notes, and publishing metadata (version identifiers, authorship).
- Link the schedule to the relevant location scope via participations (e.g., participation_type `location_scope`). The parent/child relationship enforces that all child shifts inherit the schedule’s temporal bounds.
- Versioning strategy: rather than mutating an existing schedule, spawn a new `schedule` event when the plan changes, optionally referencing the prior schedule ID in `properties.previous_schedule_id`.

## Question 3 — Draft vs published schedules
> 3 Schedules can be published and have draft states

- Use the built-in `events.status` states for draft → active transitions. Draft schedules stay invisible to workers until status becomes `active`; publishing-specific timestamps can live in `properties`.
- Maintain publish metadata (`published_at`, `published_by_entity_id`) in the schedule properties to keep the core schema clean while retaining full auditability.
- When republishing, either reuse the same event with a new status transition or create a successor `schedule` event so both drafts and live versions are traceable.

## Question 4 — Worker-to-shift linking with conditions
> 4 Workers can be linked to shifts based on some conditions

- Represent worker eligibility via participations on the schedule or shift event:
  - `participation_type: "worker_assignment"` for a committed placement.
  - `participation_type: "candidate_worker"` when the worker is merely eligible or bidding.
- Persist gating criteria (skills, certifications, bidding rank) inside participation `properties`. Because participations are temporal, a worker can be tied to multiple portions of the same shift (`start_time`/`end_time` on the participation capture partial coverage).
- Existing uniqueness constraints on `[participant_id, event_id, participation_type]` prevent duplicates, while overlap prevention lives in the Shifts context per `specs/04-temporal-modeling.md`.

## Question 5 — Plan structure vs clocking and payroll pieces
> 5 Shifts have breaks and tasks, breaks and tasks are sort of at the same level in that they represent the "plan" for what happened, and then clock in and clock out records are kind of something else which might or might not be linked to a shift and / or a break / tasks / other embedded entity. Then clock in and clock out records can be combined together to create a clocked time period which in turn might or might not be linked to a shift, break, task etc etc and then. Then that clocked time period might be subdivded into payroll pieces

- Plan layer: shifts remain events under their schedule (or directly under an employment when ad-hoc). Each shift may parent `work_period`, `break`, or `task` events to represent the intended plan; all three share the same temporal validation rules (child intervals fully inside the parent) and leverage JSONB properties (`"is_paid"`, `"task_code"`, `"expected_output"`) for plan details and attribution metadata such as `"planned_by_entity_id"`.
- Actual layer: model raw punches as `clock_event` events (one per physical interaction). Consolidate contiguous punches into `clock_period` events (parent may be a shift or free-standing). `clock_period` events can themselves parent `payroll_piece` events that subdivide actual time into cost buckets (cost center, job code, union rule). Because clocks might exist without shifts, linking is optional: use participations (`participation_type: "planned_shift_reference"`) or properties to reference plan artifacts when available, but never block ingestion if no plan exists. Track reconciliation status in properties (e.g., `"exception_state": "missing_clock_out"`) so auditors can compare plan vs actual by joining shift IDs stored in both the plan events and clock periods.

## Question 6 — Effective-dated pay data
> 6 Effective dates for things like pay rates etc etc

- Store pay rates, premiums, and rule overrides as their own events (e.g., `compensation_rate`) parented to the employment event. The event’s `start_time`/`end_time` define the valid window; rate attributes live in properties (`"currency"`, `"base_rate"`, `"overtime_multiplier"`).
- When generating payroll, resolve the applicable compensation event for each `payroll_piece` by querying events active at the clocked interval’s timestamps, ensuring bi-temporal clarity without schema churn.

## Data Questions (To Resolve Before Implementation)
1. Does the location hierarchy require multi-parent support or strict trees? (Current plan assumes a single parent via `location_membership` events.)
2. Should schedules exist as reusable templates (no direct parent) or always attach to a specific hierarchy node?
3. What granularity do payroll pieces need (per cost center, per job code, per union rule)?
4. Are break/task events sufficient for plan detail, or do we need additional event types (e.g., `handoff`, `travel`)?

## Suggested Validation Steps
1. Unit-test new event types and participations inside the relevant contexts (`mix test test/mosaic/shifts_test.exs`, etc.) to verify hierarchy bounds, draft/publish transitions, and worker assignment rules.
2. Add property casting/validation tests to guarantee JSONB schemas stay consistent (`specs/08-properties-pattern.md` guidelines).
3. Once contexts are wired, run `mix precommit` before shipping changes as required by repo guidance.
