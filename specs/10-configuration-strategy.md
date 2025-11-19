# Configuration Strategy & Composability

## Purpose
- Capture how Mosaic can turn domain variability (labor laws, workflows, integrations) into configuration rather than one-off code.
- Answer four guiding questions around templating, global rollout, composable primitives, and reusable patterns, plus document follow-up items.
- Anchor the discussion with practical examples (e.g., `calculate_net_hours/1`) that must migrate from bespoke functions to configurable constructs.

## Question 1 — Fast configuration & templating
> 1 How can we make creating configurations incredibly fast and easy, e.g. templating etc

- **Blueprint catalog:** Maintain predefined “blueprints” for common scenarios (retail store, warehouse inbound, nurse scheduling). A blueprint is just a bundle of event types, property defaults, participation roles, and rule scripts serialized as JSON/YAML. Provisioning a new tenant becomes “apply blueprint + tweak overrides.”
- **Composable property schemas:** Expose reusable fragments (e.g., `money`, `duration`, `geo_address`) that can be embedded in event/property definitions via `$ref`-style references. Eliminates repeated schema boilerplate when crafting new configuration forms.
- **Rules-as-data:** Instead of scattering logic like `calculate_net_hours/1`, store rule graphs in the properties JSON (or a dedicated `rules` table) referencing primitives such as `worked_hours`, `break_duration`, `overtime_multipliers`. Evaluate via a rule engine (see Question 3) so changing net-hours behavior is a configuration change.
- **Admin UX accelerators:** Provide UI wizards that stamp out hierarchy, event types, and participation templates in one flow. Tie them to the blueprint catalog so “Create UK Distribution Center” pre-fills employment policies, default shift structures, and pay rules.

## Question 2 — Multi-country & sector expansion through configuration
> 2 How can we make it trivial to go into lots more countries and sectors purely through configuration

- **Localization layers:** Separate legal calendars, pay frequencies, currency/rounding rules, and statutory leave requirements into country-specific configuration packs (e.g., `config/countries/uk.json`). Attach them to organizations via participations so switching a site’s locale is declarative.
- **Regulation modules:** Model compliance artifacts (accrual caps, rest-period minimums, premium triggers) as event-type behaviors referenced by the rule engine. Provide templates for each jurisdiction so extending into, say, Spain is “install `es_default` pack” rather than writing new code paths.
- **Sector adapters:** For vertical-specific needs (healthcare credentialing, logistics route planning), ship optional bundles of event types + validations. Bundles register themselves in the event-type registry and can be toggled per tenant.
- **Data-driven UI:** Drive LiveView forms from the property schemas defined in configuration so once a new country adds a “Sunday premium” field, the UI renders it without code deployments.

## Question 3 — Assembling primitives into new products (ATS, LMS, etc.)
> 3 How can we make it possible to assemble the primitives we create into "other things", e.g. ATS, LMS

- **Unified primitives:** Ensure events/participations/entities remain generic enough that “candidate application” or “course enrollment” are just new event types, not new tables. Their workflows (status pipelines, notifications) hook into the same rule engine.
- **Graph-based rule engine:** Introduce a configuration-driven engine where nodes represent primitive operations (create event, assign participant, evaluate temporal overlap, compute `calculate_net_hours`). Edges represent orchestration. By wiring primitives differently, we can express ATS pipelines, LMS progress, or workforce scheduling without new Elixir modules.
- **Composable task library:** Publish reusable functions (e.g., `sum_child_durations`, `apply_rate`, `enforce_overlap_rule`) as versioned building blocks referenced by name in configuration. The earlier `calculate_net_hours/1` example becomes `net_hours = sum("work_period") - sum_unpaid("break")`, both resolved by configurable tasks.
- **Interface contracts:** Define standard schemas for surfaces like “form step,” “approval,” “document upload,” so primitives plug into ATS or LMS UI flows with minimal glue.

## Question 4 — Reusable patterns (time bounds, audit trails, accruals, etc.)
> 4 Where have we got patterns that we end up re-inventing over and over again throughout Sona (e.g. things being time bound, audit trails, accruals, layering of time concepts etc)

- **Temporal macros:** Canonicalize patterns such as valid-time + transaction-time, overlap detection, and layered time concepts into helper modules or rule-engine components. Every feature references the same primitives instead of re-implementing `validate_no_overlap`.
- **Audit trail standard:** Enforce that every configurable action emits event + participation records plus an `activity_log` entry (who, what, when). Provide a single UI component for rendering audit chains so new modules inherit it automatically.
- **Accrual engines:** Package accrual calculation as a declarative spec (`source_events`, `rate`, `cap`, `carryover_rules`). Any module needing balances (leave, training credits, budget hours) reuses the same processor.
- **Layered configuration inheritance:** Define a hierarchical configuration resolution (global → country → organization → location → team). This prevents re-inventing override logic and makes the system’s behavior predictable no matter how many layers are involved.

## Follow-up Items & Decisions
1. **Rule/blueprint format — DECIDED:** Store definitions as JSON so they can be versioned, diffed, and easily transported through APIs/CLI tools.
2. **Rule engine — DECIDED:** Use the existing RETE engine implementation as the runtime for executing JSON-defined rule graphs.
3. **Tenant customization vs. shared updates — NEED PLAN:** Suggested options:
   - Version every blueprint/config pack and ship migrations that tenants opt into (similar to database migrations).
   - Introduce feature-flag layers so tenants can preview blueprint updates before promoting them to production sites.
   - Maintain “delta” overlays per tenant that sit atop shared blueprints; when upstream changes arrive, merge via structured change sets rather than manual edits.
4. **Governance question clarified:** We need a lightweight review process ensuring new product work first asks “can this be expressed as a reusable primitive or blueprint update?” before implementing bespoke code. Examples include checklist items in design docs, architecture review gates, or lint-style tooling that flags direct schema changes when a configuration approach exists.
