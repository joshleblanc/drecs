# Drecs Roadmap
 
This document is the stable reference for planned `drecs` improvements.
 
## Constraints
 
- **Single-file library**: All features must live in `lib/drecs.rb` for easy DragonRuby inclusion.
- **Performance-first hot paths**: Preserve the current SoA/archetype iteration model and avoid per-entity allocations in the inner loop.
- **Backwards compatible where practical**: Prefer additive APIs and maintain existing behavior unless there is a compelling reason.
 
## Guiding Principles
 
- **Archetypes are the source of truth**: Keep component storage columnar and chunk-iterable.
- **Queries should compile**: Provide ways to pre-build/retain query metadata to avoid repeated setup.
- **World mutations during iteration should be safe**: Encourage deferred commands.
 
## Milestones (Phased)
 
Each phase should be shippable on its own.
 
### Phase 1: Query Filters (High Priority)
 
**Goal**: Make queries expressive enough for real games without sacrificing speed.
 
**Proposed API additions**:
 
```ruby
world.query(Position, Velocity, without: Frozen)
world.query(Position, any: [Player, Enemy])
world.each_entity(Position, without: Dead) { |id, pos| ... }
 
# Pre-cached query variant
q = world.query_for(Position, Velocity, without: Frozen)
q.each { |entity_ids, positions, velocities| ... }
```
 
**Acceptance criteria**:
 
- `without:` excludes archetypes that include any of the excluded components.
- `any:` only matches archetypes that include at least one of the listed components.
- Filters participate in caching (no repeated scanning of archetypes per call once cached).
 
**Notes**:
 
- Keep the current `query` block form as the fastest path.
- Prefer normalized, frozen cache keys to avoid churn.
 
### Phase 2: Change Detection for Queries (High Priority)
 
**Goal**: Allow systems to only process entities whose relevant components changed since the last run.
 
**Proposed API**:
 
```ruby
world.query(Position, changed: [Position]) do |entity_ids, positions|
  # only entities whose Position changed
end
 
# Optional extensions
world.query(Position, added: [Position]) { ... }
world.query(Position, removed: [Position]) { ... }
```
 
**Acceptance criteria**:
 
- A monotonic world tick/epoch exists (internal) and can be advanced each `tick`/`schedule` run.
- `set_component` / `set_components` / `add_component` mark components as changed.
- Archetype migrations preserve correctness (either preserve timestamps or conservatively mark changed).
- Change filtering is efficient (no per-entity hash lookups in the inner loop).
 
**Notes**:
 
- Implementation likely requires per-component parallel metadata arrays (e.g. `changed_at[]`).
- The first implementation can focus on `changed:` only; `added:` / `removed:` can follow.
 
### Phase 3: Event System (Medium Priority)
 
**Goal**: Provide a lightweight way for systems to communicate without direct coupling.
 
**Proposed API**:
 
```ruby
world.send_event(DamageEvent.new(target_id, amount))
world.each_event(DamageEvent) { |evt| ... }
world.clear_events!(DamageEvent)
```
 
**Acceptance criteria**:
 
- Events are buffered per frame/tick and can be drained deterministically.
- Minimal allocations in hot loops (events are already allocations; iteration should not add more).
 
### Phase 4: Bundles (Medium Priority)
 
**Goal**: Standardize common spawn/insert patterns.
 
**Proposed API**:
 
```ruby
PlayerBundle = Drecs.bundle(Position, Velocity, Health)
world.spawn_bundle(PlayerBundle, Position.new(0,0), Velocity.new(0,0), Health.new(10,10))
 
# Or a block-based bundle
world.spawn_bundle(PlayerBundle) { |b| b[Position] = Position.new(0,0) }
```
 
**Acceptance criteria**:
 
- Bundle usage avoids repeated signature normalization for common spawns.
- Works for both class components and symbol/hash components (if supported).
 
### Phase 5: System Scheduling and Run Conditions (Medium Priority)
 
**Goal**: Provide an explicit scheduling layer without breaking `World#tick`.
 
**Proposed API**:
 
```ruby
world.add_system(:movement, after: :input, if: ->(w, args) { !w.resource(:paused) }) do |w, args|
  # ...
end
 
world.tick(args) # uses ordering/conditions if defined
```
 
**Acceptance criteria**:
 
- Systems can declare ordering (`before:`/`after:`) by name.
- Systems can declare run conditions (`if:`/`unless:`).
- Execution order is deterministic.
 
**Notes**:
 
- Parallelism is not a goal for MRI Ruby.
- This can be implemented as an optional feature: if no metadata is used, keep the existing fast array iteration.
 
### Phase 6: State Machines (Low/Medium Priority)
 
**Goal**: Provide a small, opt-in state mechanism useful for menus, modes, and gameplay loops.
 
**Proposed API**:
 
```ruby
world.insert_resource(:state, :playing)
world.add_system(:pause_menu, if: ->(w, _) { w.resource(:state) == :paused }) { ... }
```
 
**Acceptance criteria**:
 
- A recommended pattern exists (resource + scheduling conditions) even if no dedicated state type is introduced.
 
### Phase 7: Observers / Component Hooks (Low Priority)
 
**Goal**: React to component lifecycle events (added/changed/removed) without polling.
 
**Proposed API**:
 
```ruby
world.on_added(Position) { |world, entity_id| ... }
world.on_removed(Health) { |world, entity_id| ... }
world.on_changed(Velocity) { |world, entity_id| ... }
```
 
**Acceptance criteria**:
 
- Hooks run deterministically and do not break iteration safety.
- Hooks integrate with deferred mutations (hooks may enqueue work).
 
### Phase 8: Single Entity Query Access (Low Priority)
 
**Goal**: Make it ergonomic to retrieve multiple components from a single entity efficiently.
 
**Proposed API**:
 
```ruby
pos, vel = world.get_many(entity_id, Position, Velocity)
world.with(entity_id, Position, Velocity) { |pos, vel| ... }
```
 
**Acceptance criteria**:
 
- Avoid repeated archetype hash lookups for each component when retrieving many.
- Safe behavior if entity or components are missing (clear return convention).
 
### Phase 9: Entity Relationships (Low Priority)
 
**Goal**: Support parent/child and general graph relationships.
 
**Proposed approach**:
 
- Provide relationship components (e.g. `Parent`, `Children`) and helper APIs.
- Keep the core ECS storage model unchanged.
 
**Acceptance criteria**:
 
- Relationship updates are consistent with deferred mutation.
- Common traversal patterns are supported (children iteration, subtree despawn).
 
## Non-Goals (for now)
 
- Automatic parallel system execution.
- Borrow-checker-like safety guarantees.
- Multi-file refactor of the library itself.
