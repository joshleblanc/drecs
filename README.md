# Drecs

Drecs is a high-performance archetype-based ECS (Entity Component System) implementation for [DragonRuby](https://dragonruby.org/toolkit/game).

## Features

- **Archetype-based storage** - Entities with the same component signatures are stored together for cache-friendly iteration
- **High-speed queries** - Pre-computed component stores eliminate hash lookups in hot paths
- **Query filters** - `without:` and `any:` allow expressive filtering without manual branching
- **Change detection** - `changed:` filtering enables efficient incremental updates
- **Event system** - `send_event` / `each_event` / `clear_events!` for decoupled system communication
- **Bundles** - Precomputed signatures for common spawns via `Drecs.bundle` and `spawn_bundle`
- **System scheduling** - Named systems with `after:`/`before:` ordering and `if:` run conditions
- **Observer hooks** - `on_added` / `on_removed` / `on_changed` for component lifecycle callbacks
- **Single-entity access** - `get_many` / `with` for efficient multi-component retrieval
- **Entity relationships** - `Parent` / `Children` components with helper APIs
- **Automatic archetype cleanup** - Empty archetypes are removed to prevent memory growth
- **Flexible component operations** - Add, remove, or batch-update components with archetype migration
- **Debug/inspection tools** - Built-in methods to understand world state and performance, plus an in-game debug overlay
- **Ergonomic helpers** - `Drecs.tag`, `Drecs.component`, `Drecs::Component` mixin, `find_entity`, `cached_query`, `event?`/`event_count`, `fetch_resource`, `snapshot`/`restore`, `validate!`, `dump`, and more

## Installation

In a dragonruby project, run the following in your dragonruby console:

```bash
GTK.download_stb_rb "https://github.com/joshleblanc/drecs/blob/master/lib/drecs.rb"
```

This downloads the single `lib/drecs.rb` file — that's all you need.

## Usage

Require drecs at the top of your `main.rb`. Use whichever path matches how you
installed it:

```ruby
# Installed via GTK.download_stb_rb (vendored under the author/repo path):
require "joshleblanc/drecs/drecs.rb"

# Or, if you vendored the file yourself into your project's lib/:
require "lib/drecs"
```

## Canonical API (start here)

Drecs ships many aliases for backwards compatibility, which can make it hard to
know what to reach for. **Prefer the canonical method in each row below**; the
others are kept working but are not the documented path.

| Operation                     | Canonical             | Aliases (still work)                     |
|-------------------------------|-----------------------|------------------------------------------|
| Create an entity              | `spawn`               | `create`, `<<`                           |
| Read one component            | `get_component`       | `get`, `[]`                              |
| Add/replace one component     | `set_component`       | —                                        |
| Add/replace many (one move)   | `set_components`      | `set`, `upsert`                          |
| Add a *new* component type    | `add_component`       | `add`                                    |
| Remove a component            | `remove_component`    | `remove`                                 |
| Has a component?              | `has_component?`      | `has?`, `component?`                     |
| Entity alive?                 | `entity_exists?`      | `exists?`, `alive?`                      |
| Destroy entities              | `destroy`             | `delete`, `despawn`                      |
| Per-entity iteration (AoS)    | `each_entity`         | `each`, `query`                          |
| Batched iteration (SoA, fast) | `each_chunk`          | —                                        |
| Cached hot-path query         | `cached_query`        | `query_for`                              |
| First match (id + components) | `first_entity`        | `first`                                  |
| First match (id only)         | `find_entity`         | —                                        |

### Per-entity vs batched iteration

There are two ways to iterate, with clearly separated names:

```ruby
# Per-entity (AoS) — `query` / `each_entity`. Yields (entity_id, *components)
# one entity at a time. With or without a block:
world.each_entity(Position, Velocity) do |id, pos, vel|
  pos.x += vel.dx
end
id, pos, vel = world.query(Position, Velocity).first   # no block → enumerator

# Batched (SoA, fast path) — `each_chunk`. Yields the entity_ids array followed
# by one parallel array per component, per archetype chunk:
world.each_chunk(Position, Velocity) do |ids, positions, velocities|
  i = 0
  while i < ids.length
    positions[i].x += velocities[i].dx
    i += 1
  end
end
```

`query` and `each_entity` are interchangeable (per-entity). Reach for
`each_chunk` only when you specifically want the SoA arrays for a tight loop.

### Creating a World

```ruby
require 'joshleblanc/drecs/drecs.rb'

def boot(args)
  args.state.world = Drecs::World.new
end
```

### Observer Hooks

Register component lifecycle hooks to react when data is added, removed, or changed. Hooks run in deterministic order based on component class/signature sorting, and can enqueue deferred work.

```ruby
world.on_added(Position) do |w, entity_id, component|
  # component was added (or spawned)
end

world.on_changed(Health) do |w, entity_id, component|
  # component was updated via add_component or set_components
end

world.on_removed(Velocity) do |w, entity_id, component|
  # component was removed or entity destroyed
end
```

### Defining Components

Components can be `Drecs.component` classes, the `Drecs::Component` mixin, or plain hashes for rapid prototyping:

**Class Components (recommended for production):**

```ruby
Position = Drecs.component(:x, :y)
Velocity = Drecs.component(:dx, :dy)
Health   = Drecs.component(:current, :max)
Tag      = Drecs.component(:name)

# Tag components (zero-field markers) — use Drecs.tag
Player = Drecs.tag(:player)
Enemy  = Drecs.tag(:enemy)
```

`Drecs.component(*members)` returns a class whose fields are stored as plain
`@-ivars` (getter/setter accessors plus a Struct-ish `members`/`values`/`[]`
API). It is **not** a `Struct` — storing fields as ivars is what makes the
accessors uniform with the rest of drecs, and it sidesteps the hot-reload
trap of `class X < Struct.new(...)` (see Pitfalls). `Drecs.tag(name)` returns a
zero-field marker class (also **not** a `Struct`) that introspects cleanly on
both the class and its instances (`Player.tag_name == :player`,
`Player.new.tag_name == :player`).

When a component needs **methods** or **real class constants**, use the
`Drecs::Component` mixin so it reads as an ordinary, named class — no
`X = Drecs.component(...)` + `class X` reopen dance:

```ruby
class Velocity
  include Drecs::Component
  component :dx, :dy

  def initialize(dx = 0, dy = 0) # optional: add defaults
    @dx = dx
    @dy = dy
  end

  def moving? = dx != 0 || dy != 0
  def speed   = Math.sqrt(dx * dx + dy * dy)
end

class Tile
  include Drecs::Component
  component :type

  TILE_FLOOR = 0   # a real class constant: `Tile::TILE_FLOOR` works
end
```

For a quick one-liner with methods, `Drecs.component` also accepts a block
(like `Struct.new`): `Velocity = Drecs.component(:dx, :dy) { def speed = ... }`.
Note that constants assigned inside that block are **not** class constants
(Ruby scopes them lexically) — use the mixin form when you need
`Tile::TILE_FLOOR`.

**Hash Components (great for MVPs and prototyping):**

```ruby
# No need to define component structures upfront
# Just use hashes with symbol keys directly
entity = world.spawn({
  position: { x: 100, y: 100 },
  velocity: { dx: 5, dy: 0 },
  sprite: { r: 255, g: 0, b: 0 }
})

# Query using symbols instead of classes
world.each_entity(:position, :velocity) do |entity_id, position, velocity|
  # ...
end
```

See the `samples/snake` example for a complete game built entirely with hash components.

### Creating Entities

Entities are created with the `spawn` method, passing component instances:

```ruby
# Spawn an entity with multiple components
player_id = world.spawn(
  Position.new(100, 100),
  Velocity.new(0, 0),
  Health.new(100, 100),
  Player.new
)

# Spawn enemies
enemy_id = world.spawn(
  Position.new(200, 200),
  Health.new(50, 50),
  Enemy.new
)
```

### Bulk Creation

```ruby
world.spawn_many(10_000,
  Position.new(0, 0),
  Velocity.new(1, 1),
  Particle.new
)
```

### Bundles

Bundles are a way to predefine common component sets (archetypes) so repeated spawns avoid repeated signature work.

```ruby
PlayerBundle = Drecs.bundle(Position, Velocity, Health)

player_id = world.spawn_bundle(PlayerBundle,
  Position.new(0, 0),
  Velocity.new(0, 0),
  Health.new(10, 10)
)
```

You can also use the block form:

```ruby
PlayerBundle = Drecs.bundle(Position, Velocity, Health)

player_id = world.spawn_bundle(PlayerBundle) do |b|
  b[Position] = Position.new(0, 0)
  b[Velocity] = Velocity.new(0, 0)
  b[Health] = Health.new(10, 10)
end
```

Bundles work with hash/symbol components too:

```ruby
ActorBundle = Drecs.bundle(:position, :velocity, :sprite)

id = world.spawn_bundle(ActorBundle, {
  position: { x: 100, y: 200 },
  velocity: { dx: 1, dy: 0 },
  sprite: { r: 255, g: 255, b: 255 }
})
```

### Managing Components

```ruby
# Add a component to an existing entity
world.add_component(entity_id, Velocity.new(5, 0))

# Remove a component
world.remove_component(entity_id, Velocity)

# Batch update multiple components (more efficient than multiple add_component calls)
world.set_components(entity_id,
  Position.new(150, 150),
  Velocity.new(10, 5)
)

# Get a specific component
pos = world.get_component(entity_id, Position)

# Check if entity has a component
if world.has_component?(entity_id, Health)
  # ...
end

# Check if entity exists
if world.entity_exists?(entity_id)
  # ...
end
```

### Querying Entities

For per-entity iteration, use `each_entity` (or its alias `query`):

```ruby
# Iterate over individual entities
world.each_entity(Position, Velocity) do |entity_id, pos, vel|
  pos.x += vel.dx
  pos.y += vel.dy
end

# Use entity_id to modify components
world.each_entity(Health, Enemy) do |entity_id, health|
  if health.current <= 0
    world.destroy(entity_id)
  end
end
```

For the fastest batch processing, use `each_chunk`, which yields the
`entity_ids` array followed by one parallel array per component:

```ruby
# each_chunk yields entity_ids first, then component arrays (SoA)
world.each_chunk(Position, Velocity) do |entity_ids, positions, velocities|
  # Arrays are aligned by index
  i = 0
  while i < entity_ids.length
    pos = positions[i]
    vel = velocities[i]
    pos.x += vel.dx
    pos.y += vel.dy
    i += 1
  end
end
```

For maximum performance in hot loops (e.g., systems running every frame), use `cached_query` to pre-cache the query structure. This avoids signature normalization and hash lookups entirely during iteration. A cached `Query#each` yields SoA arrays, like `each_chunk`.

```ruby
# In your system initialization:
@movement_query = world.cached_query(Position, Velocity)

# In your tick/update method:
@movement_query.each do |entity_ids, positions, velocities|
  # ... tight loop logic ...
end
```

#### Query Filters

You can filter queries without per-entity `has_component?` checks:

```ruby
# Entities with Position but without Velocity
world.each_entity(Position, without: Velocity) do |entity_id, pos|
  # ...
end

# Entities with Position and (Player OR Enemy) — SoA batch form
world.each_chunk(Position, any: [Player, Enemy]) do |entity_ids, positions|
  # ...
end
```

#### Change Detection

You can query for entities whose components changed on the current change tick:

```ruby
# Advance the change tick once per frame (if you are not calling world.tick(args))
world.advance_change_tick!

# Mutations mark components as changed for the current tick
world.set_component(entity_id, Position.new(10, 10))

# Only entities whose Position changed this tick
world.each_entity(Position, changed: [Position]) do |id, pos|
  # ...
end
```

If you use `world.tick(args)` to run systems, it automatically calls `advance_change_tick!` once per tick.

#### Events

Events provide a lightweight way for systems to communicate without direct coupling.

Events are buffered by type/key, can be iterated deterministically, and can be cleared explicitly.

```ruby
DamageEvent = Struct.new(:target_id, :amount)

# Send an event (keyed by class)
world.send_event(DamageEvent.new(enemy_id, 5))

# Send an event (keyed by symbol)
world.send_event(:log, { msg: "hit!" })

# Drain/iterate events
world.each_event(DamageEvent) do |evt|
  puts "Damage #{evt.target_id} for #{evt.amount}"
end

# Clear events (all types)
world.clear_events!

# Clear only one event type
world.clear_events!(DamageEvent)
```

By default, events are cleared when the world advances its change tick.
This means that if you call `world.tick(args)` (or call `advance_change_tick!` once per frame), events are naturally scoped to a single tick.

#### Deferring World Mutations

Structural changes (destroy/spawn/add/remove) should be batched. drecs exposes two
flavors so the choice between defer-and-flush and apply-now is explicit:

```ruby
# Inside iteration, or whenever you want "buffer and flush" semantics:
world.commands { |cmd| cmd.destroy(entity_id) }

# When you need the change to be visible RIGHT NOW (e.g. mid-frame, between
# iteration and the next frame, or anywhere the deferred semantics don't fit):
world.commands! { |cmd| cmd.spawn(Position.new(0, 0)) }
```

`commands` always defers — the buffered mutations run at the next flush point.
`tick(args)` calls `flush_defer!` at the end of every frame, so the common case
"queue inside a system, run before the next frame" works automatically. Inside
iteration, the flush happens when the iterator ends.

`commands!` always applies immediately. Use it when you specifically want the
mutation to be visible to subsequent calls in the same code path.

`defer { ... }` and `flush_defer!` are still available for low-level control.

To find just the first matching entity, use `first_entity`:

```ruby
# Returns [entity_id, component1, component2, ...] or nil if no match
result = world.first_entity(Position, Velocity)
if result
  entity_id, pos, vel = result
  puts "Found entity #{entity_id} at position (#{pos.x}, #{pos.y})"
end

# Or use with a block
world.first_entity(Player, Health) do |entity_id, player, health|
  puts "Player health: #{health.current}/#{health.max}"
end
```

If you only need the entity_id (e.g. for a "is there one?" check or to feed into
another operation), use `find_entity`:

```ruby
# First matching entity id, or nil
id = world.find_entity(Position, Velocity)

# Predicate form: return the first entity the block returns truthy for
id = world.find_entity(Position, Velocity) { |_id, pos, _vel| pos.x > 500 }
```

`find_entity` is the right choice when the components themselves don't matter;
`first_entity` is the right choice when you need them.

### Single Entity Component Access

Retrieve multiple components from one entity without repeated store lookups:

```ruby
pos, vel = world.get_many(entity_id, Position, Velocity)

world.with(entity_id, Position, Velocity) do |pos, vel|
  puts "Position: #{pos.x}, #{pos.y}"
end
```

### Entity Relationships

Use the built-in `Parent` and `Children` components with helpers to manage hierarchies:

```ruby
parent_id = world.spawn(Position.new(0, 0))
child_id = world.spawn(Position.new(10, 10))

world.set_parent(child_id, parent_id)

world.children_of(parent_id) # => [child_id]
world.parent_of(child_id)    # => parent_id

world.clear_parent(child_id)
world.destroy_subtree(parent_id)
```

### Destroying Entities

```ruby
# Destroy a single entity
world.destroy(entity_id)

# Destroy multiple entities at once (more efficient)
world.destroy(entity_id1, entity_id2, entity_id3)

# Collect entities to destroy, then destroy in batch
to_destroy = []
world.each_entity(Health) do |entity_id, health|
  to_destroy << entity_id if health.current <= 0
end
world.destroy(*to_destroy) unless to_destroy.empty?
```

### Debug and Inspection

```ruby
# Get entity count
puts "Entities: #{world.entity_count}"

# Get archetype count
puts "Archetypes: #{world.archetype_count}"

# Get detailed archetype statistics
world.archetype_stats.each do |stat|
  puts "Archetype [#{stat[:components].join(', ')}]: #{stat[:entity_count]} entities"
end

# List every component class/symbol that's currently in use
puts "Components: #{world.component_classes.inspect}"

# Dump the whole world as a multi-line String — great for the DragonRuby
# console when the in-game debug overlay isn't available.
puts world.dump

# Development-time integrity check. Walks every archetype and verifies that
# stores, rows, and the entity tables are mutually consistent. Raises
# `Drecs::IntegrityError` if anything is off. Cheap to call.
world.validate!
```

### Snapshot, Restore, and Cached Queries

```ruby
# Capture the entire world state (entities + components + resources + events)
# into a Hash. Components are copied into fresh instances (nested Array/Hash
# field values are dup'd one level deep) so mutating the live world doesn't
# affect the snapshot. NOTE: mruby has no Marshal, so structures nested more
# than one level deep are still aliased.
snap = world.snapshot

# ...later, in another world or another session. Entities are re-id'd
# sequentially from 0; built-in Parent/Children components are remapped to
# the new ids automatically. If your own components store entity ids, remap
# them via the optional block, which receives { old_id => new_id }:
fresh = Drecs::World.new
fresh.restore(snap) do |id_map|
  fresh.each_entity(Targeting) { |_id, t| t.target = id_map[t.target] }
end

# If the same query runs every frame, build a cached Query once instead of
# re-normalizing the signature every call:
q = world.cached_query(Position, Velocity)
q.each { |ids, positions, velocities| ... }
```

### Event Helpers

```ruby
# Check / count / snapshot buffered events without iterating
world.event?(:hit)             # true/false
world.event_count(:hit)        # Integer
world.events(:hit)             # Array snapshot (safe to mutate)
```

### Resource Helpers

```ruby
# Insert and read like before
world.insert_resource(:score, 0)
world.resource(:score)         # nil if missing

# Or use the fetching form, which raises or falls back to a default
world.fetch_resource(:score)               # raises KeyError if missing
world.fetch_resource(:score) { 0 }         # returns 0 if missing

# Predicate
world.has_resource?(:score)     # true/false
```

### World Construction

```ruby
# Default — no duplicate-component validation (fastest hot path).
world = Drecs::World.new

# Turn on validation when shipping or debugging:
world = Drecs::World.new(validate_components: true)
```

### Resources

Resources provide global singleton state that doesn't belong to any entity, such as game time, configuration, input state, etc. They're useful for data that needs to be accessed by many systems without entity relationships.

#### Defining Resources

Resources can be plain Ruby structs or any object:

```ruby
GameTime = Struct.new(:elapsed, :delta)
GameConfig = Struct.new(:difficulty, :max_players)
Score = Struct.new(:current, :high_score)
```

#### Inserting Resources

```ruby
# Insert struct-style resource (keyed by class)
world.insert_resource(GameTime.new(0.0, 0.016))

# Insert hash-style resource (keyed by symbol)
world.insert_resource({ score: Score.new(0, 100) })

# Insert with explicit key-value
world.insert_resource(:player_name, "Player1")
```

#### Retrieving Resources

```ruby
# Retrieve by class
time = world.resource(GameTime)

# Retrieve by symbol
score = world.resource(:score)

# Retrieve by key passed during insertion
player_name = world.resource(:player_name)
```

#### Using Resources in Systems

```ruby
class TimeSystem
  def call(world, args)
    time = world.resource(GameTime)
    time.elapsed += time.delta
  end
end

class ScoreDisplaySystem
  def call(world, args)
    score = world.resource(Score)
    # Display score...
  end
end
```

#### Removing Resources

```ruby
world.remove_resource(GameTime)
world.remove_resource(:score)
```

### System Scheduling and Run Conditions

You can register named systems on the world and let `world.tick(args)` run them in a deterministic order.

```ruby
world.add_system(:input) { |w, args| }
world.add_system(:movement, after: :input) { |w, args| }
world.add_system(:render, after: :movement) { |w, args| }

world.tick(args)
```

Run conditions can be provided with `if:`:

```ruby
world.insert_resource(:paused, false)

world.add_system(:movement,
  after: :input,
  if: ->(w, _args) { !w.resource(:paused) }
) do |w, args|
  # ...
end
```

If you don't use named scheduled systems, `world.tick(args)` will continue to run any systems added via the original `add_system(callable)` API.

## Performance Tips

1. **Use `each_chunk` for batch operations** - When processing many entities, `each_chunk` is faster than `each_entity`/`query` because it works with raw SoA arrays
2. **Use `cached_query` for hot-path queries** - If the same query runs every frame, build a `cached_query` once and reuse it; signature normalization runs once instead of every call
3. **Batch component changes** - Use `set_components` instead of multiple `add_component` calls to avoid repeated archetype migrations
4. **Batch entity destruction** - Collect entity IDs and call `destroy(*ids)` once instead of destroying individually
5. **Component reuse** - Modify component values in-place when possible instead of creating new component instances
6. **Empty archetype cleanup** - The library automatically cleans up empty archetypes, preventing memory growth

## Multi-File Projects

Since entities are just integers and components are just data, DrECS works naturally with multi-file projects. You can organize your code by creating:

- **Component files** - Each component as a simple class/struct in its own file
- **System files** - Plain Ruby classes with a `call(world, args)` method
- **Main file** - Requires everything and orchestrates the game loop

```ruby
# app/components/position.rb
class Position
  include Drecs::Component
  component :x, :y
end

# app/systems/movement_system.rb
class MovementSystem
  def call(world, args)
    world.each_entity(Position, Velocity) do |id, pos, vel|
      pos.x += vel.x
      pos.y += vel.y
    end
  end
end

# app/main.rb
require_relative 'components/position.rb'
require_relative 'systems/movement_system.rb'

def boot(args)
  args.state.world = Drecs::World.new
  args.state.world.clear_schedule!
  args.state.world.add_system(:movement, system: MovementSystem.new)
end

def tick(args)
  args.state.world.tick(args)
end
```

## Examples

See the `samples` directory for complete examples:

- **trivial** - Basic ECS usage demonstrating core concepts, including scheduling and run conditions
- **boids** - High-performance flocking simulation with 2500+ entities (uses bundles)
- **ants** - Ant colony simulation with pheromones and state machines
- **avoider** - Arcade micro-game demonstrating `without:`/`any:` query filters, `changed:`-driven incremental rendering, and bundles
- **spaceshooter** - Multi-file project structure with separate component and system files (uses bundles, events, and scheduling)
- **asteroids** - Classic Asteroids game with multi-file architecture (uses scheduling and run conditions)
- **snake** - Complete game built using hash components (great for MVPs and rapid prototyping)
- **tetris** - Classic Tetris implementation with hash components
- **flappy** - Flappy Bird clone using hash components with dynamic pipe spawning
- **performance** - Interactive benchmarking suite showing performance at scale (up to 100k entities)

## Development

Samples are available in the samples directory. The main entry point is `app/main.rb` which loads a specific sample using CLI arguments.

To run samples, use DragonRuby with the appropriate sample argument:
```bash
dragonruby . --sample boids
dragonruby . --sample ants
dragonruby . --sample trivial
dragonruby . --sample avoider
```

## Known Pitfalls

A few things that bite new drecs users. These are documented up front so you
don't lose an afternoon to them.

### Struct subclasses break DragonRuby hot reload

```ruby
class PlayerGrid < Struct.new(:grid_x, :grid_y)   # ← THIS BREAKS HOT RELOAD
  ...
end
```

If you define a component as a `Struct` *subclass* (with `class ... < Struct.new(...)`),
DragonRuby's hot reload will throw `superclass mismatch for class PlayerGrid`
on the next reload and you'll need to `GTK.reboot` (Shift+Ctrl+R / Cmd+R).
This is a DragonRuby / mruby constraint, not a drecs bug.

**Fix:** use the `Drecs.component` assignment form, or — when you want a named
class with methods/constants — the `Drecs::Component` mixin:

```ruby
PlayerGrid = Drecs.component(:grid_x, :grid_y)
# or, when you need methods and/or class constants:
class PlayerGrid
  include Drecs::Component
  component :grid_x, :grid_y

  TILE_SIZE = 32
  def to_pixel = { x: grid_x * TILE_SIZE, y: grid_y * TILE_SIZE }
end
```

Both reopen the *same* named class on reload (no anonymous superclass), so
hot reload stays happy. Avoid `class Foo < Struct.new(...)`.

### Per-entity (`query`/`each_entity`) vs batched (`each_chunk`)

`query` and `each_entity` are the per-entity (AoS) view; `each_chunk` is the
Structure-of-Arrays (SoA) fast path. They are now clearly distinct methods, so
there is no longer a footgun where the same method changes shape based on the
block:

```ruby
# Per-entity — yields (entity_id, *components), one entity at a time.
world.each_entity(Position, Velocity) do |id, pos, vel|
  pos.x += vel.dx
end
id, pos, vel = world.query(Position, Velocity).first   # no block → enumerator

# Batched (SoA) — yields the entity_ids array, then one array per component.
world.each_chunk(Position, Velocity) do |ids, positions, velocities|
  # ids[0..n], positions[0..n], velocities[0..n] — index-aligned
end
```

> **Migrating from older drecs:** the block form of `query` used to yield SoA
> arrays. It now yields per-entity tuples. Replace any
> `query(...) do |ids, positions, ...|` with `each_chunk(...)`.

### Struct components and hash components are two parallel worlds

You can use either, but they don't fully interoperate:

- Lifecycle hooks are keyed by whatever you spawned with. `on_added(Position)`
  fires for struct components; `on_added(:position)` fires for hash components.
  They do **not** cross over — a struct `Position` won't trigger a `:position`
  hook and vice versa. (See `samples/snake`, which uses `on_added(:food)` with
  hash components.)
- `world.spawn(Position.new(...))` and `world.spawn({ position: {...} })`
  create entities in different internal layouts, though queries against
  either key return the same data.
- Code review can't tell from a call site which kind is in use.

Pick one for a project and stick with it. Mixing is supported, but if you spawn
with one model and register hooks/queries against the other, they simply won't
match.

### `set_components` on archetype migration bumps everything

When `set_components` causes an entity to migrate to a new archetype (e.g. you
added a new component type), **every component on the entity** has its
`change_tick` bumped — not just the ones you touched. The reasoning: the
archetype move itself is a visible change, and downstream `changed:` filters
should see it.

If you only want "touched" semantics, stay on the same archetype (replace
existing component values, don't add new ones) or use `add_component` /
`remove_component` directly.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/drecs. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Drecs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).
