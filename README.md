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
- **Debug/inspection tools** - Built-in methods to understand world state and performance

## Installation

In a dragonruby project, run the following in your dragonruby console:

```bash
GTK.download_stb_rb "https://github.com/joshleblanc/drecs/blob/master/lib/drecs.rb"
```

## Usage

Simply `require "joshleblanc/drecs/drecs.rb"` at the top of your `main.rb`.

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

Components can be simple Ruby Structs or plain hashes for rapid prototyping:

**Struct Components (recommended for production):**

```ruby
Position = Struct.new(:x, :y)
Velocity = Struct.new(:dx, :dy)
Health = Struct.new(:current, :max)
Tag = Struct.new(:name)

# Tag components (no data)
Player = Struct.new("Player")
Enemy = Struct.new("Enemy")
```

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
world.query(:position, :velocity) do |entity_ids, positions, velocities|
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

### UI System (Drecs::UI)

Drecs ships with a lightweight ECS-driven UI module. UI elements are regular entities with UI components; the UI is updated via ECS systems just like gameplay logic.

**Setup**

```ruby
world = Drecs::World.new
Drecs::UI.install(world)
```

**Core UI Components**

- `UiNode` — tag component identifying a UI entity.
- `UiLayout(x, y, w, h, layout, padding, gap, align, justify)`
  - `x`, `y` are offsets inside the parent container.
  - `w`, `h` define the size. If `w`/`h` are `0` or `nil`, the layout system stretches to the parent’s content size (minus padding).
  - `layout` is `:column` or `:row` for child flow direction.
  - `padding` is inner spacing; `gap` is spacing between children.
  - `align`/`justify` are reserved for future alignment support.
- `UiStyle(bg, border, border_thickness, text_color)`
  - `bg` / `border` are color hashes: `{ r:, g:, b:, a: }`.
  - `border_thickness` and `text_color` are reserved for future styling.
- `UiText(text, size_enum)` — text label (rendered using DragonRuby labels).
- `UiInput(hovered, pressed, on_click)` — click handling; `on_click` gets `(entity_id, world)`.

**Example**

```ruby
UI = Drecs::UI

root = world.spawn(
  UI::UiNode.new("root"),
  UI::UiLayout.new(0, 0, args.grid.w, args.grid.h, :column, 24, 12, :start, :start)
)

panel = world.spawn(
  UI::UiNode.new("panel"),
  UI::UiLayout.new(0, 0, 420, 220, :column, 12, 8, :start, :start),
  UI::UiStyle.new({ r: 12, g: 12, b: 20, a: 220 }, { r: 50, g: 60, b: 80 }, 1, nil)
)
world.set_parent(panel, root)

button = world.spawn(
  UI::UiNode.new("button"),
  UI::UiLayout.new(0, 0, 200, 36, :row, 0, 0, :start, :start),
  UI::UiStyle.new({ r: 40, g: 120, b: 220, a: 230 }, { r: 50, g: 60, b: 80 }, 1, nil),
  UI::UiText.new("Click me", 2),
  UI::UiInput.new(false, false, ->(_id, w) { puts "clicked" })
)
world.set_parent(button, panel)
```

See `samples/ui_demo` for a full retained-mode UI example.

### Querying Entities

The `query` method returns component arrays for high-performance batch processing:

```ruby
# Query yields entity_ids first, then component arrays
world.query(Position, Velocity) do |entity_ids, positions, velocities|
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

For maximum performance in hot loops (e.g., systems running every frame), use `query_for` to pre-cache the query structure. This avoids signature normalization and hash lookups entirely during iteration.

```ruby
# In your system initialization:
@movement_query = world.query_for(Position, Velocity)

# In your tick/update method:
@movement_query.each do |entity_ids, positions, velocities|
  # ... tight loop logic ...
end
```

For per-entity iteration, use `each_entity` (more ergonomic but slightly slower):

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

#### Query Filters

You can filter queries without per-entity `has_component?` checks:

```ruby
# Entities with Position but without Velocity
world.each_entity(Position, without: Velocity) do |entity_id, pos|
  # ...
end

# Entities with Position and (Player OR Enemy)
world.query(Position, any: [Player, Enemy]) do |entity_ids, positions|
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

#### Deferring World Mutations During Iteration

When iterating entities, structural changes (destroy/spawn/add/remove) should be deferred. The recommended API is `commands`, which batches mutations safely and applies them after iteration.

```ruby
# Safely destroy entities found during iteration
world.each_entity(Health, Enemy) do |entity_id, health|
  if health.current <= 0
    world.commands { |cmd| cmd.destroy(entity_id) }
  end
end
```

Outside of iteration, `commands` applies immediately. `defer`/`flush_defer!` are still available for low-level control, but `commands` is preferred.

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

1. **Use `query` for batch operations** - When processing many entities, `query` is faster than `each_entity` because it works with raw arrays
2. **Batch component changes** - Use `set_components` instead of multiple `add_component` calls to avoid repeated archetype migrations
3. **Batch entity destruction** - Collect entity IDs and call `destroy(*ids)` once instead of destroying individually
4. **Component reuse** - Modify component values in-place when possible instead of creating new component instances
5. **Empty archetype cleanup** - The library automatically cleans up empty archetypes, preventing memory growth

## Multi-File Projects

Since entities are just integers and components are just data, DrECS works naturally with multi-file projects. You can organize your code by creating:

- **Component files** - Each component as a simple class/struct in its own file
- **System files** - Plain Ruby classes with a `call(world, args)` method
- **Main file** - Requires everything and orchestrates the game loop

```ruby
# app/components/position.rb
class Position < Struct.new(:x, :y); end

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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/drecs. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Drecs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).
