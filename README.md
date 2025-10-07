# Drecs

Drecs is a high-performance archetype-based ECS (Entity Component System) implementation for [DragonRuby](https://dragonruby.org/toolkit/game).

## Features

- **Archetype-based storage** - Entities with the same component signatures are stored together for cache-friendly iteration
- **High-speed queries** - Pre-computed component stores eliminate hash lookups in hot paths
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

The `query` method returns component arrays for high-performance batch processing:

```ruby
# Query yields entity_ids first, then component arrays
world.query(Position, Velocity) do |entity_ids, positions, velocities|
  # Arrays are aligned by index
  positions.each_with_index do |pos, i|
    vel = velocities[i]
    entity_id = entity_ids[i]
    pos.x += vel.dx
    pos.y += vel.dy
  end
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
  args.state.systems = [MovementSystem.new]
end

def tick(args)
  args.state.systems.each { |sys| sys.call(args.state.world, args) }
end
```

## Examples

See the `samples` directory for complete examples:

- **trivial** - Basic ECS usage demonstrating core concepts
- **boids** - High-performance flocking simulation with 2500+ entities
- **ants** - Ant colony simulation with pheromones and state machines
- **spaceshooter** - Multi-file project structure with separate component and system files
- **asteroids** - Classic Asteroids game with multi-file architecture (components and systems)
- **snake** - Complete game built using hash components (great for MVPs and rapid prototyping)
- **tetris** - Classic Tetris implementation with hash components
- **flappy** - Flappy Bird clone using hash components with dynamic pipe spawning
- **performance** - Interactive benchmarking suite showing performance at various scales (1K-20K entities)

## Development

Samples are available in the samples directory. The main entry point is `app/main.rb` which loads a specific sample using CLI arguments.

To run samples, use DragonRuby with the appropriate sample argument:
```bash
dragonruby . --sample boids
dragonruby . --sample ants
dragonruby . --sample trivial
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/drecs. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Drecs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).
