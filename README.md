# DrECS API Documentation

## Overview

DrECS is a lightweight Entity Component System (ECS) framework for DragonRuby Game Toolkit. It provides a flexible architecture for organizing game objects and systems with a focus on performance and ergonomics.

## Core Concepts

### Entity Component System (ECS)

DrECS follows the ECS architectural pattern:

- **Entities** are game objects represented as containers for components
- **Components** are pure data structures attached to entities
- **Systems** contain logic that processes entities with specific component combinations

## API Reference

### World

The central registry that manages entities, components, and systems.

```ruby
# Create a new world
world = Drecs.world do
  # World configuration and setup here
end
```

#### Methods

| Method | Description |
|--------|-------------|
| `entity(name = nil, &block)` | Creates a new entity or retrieves an existing one by name |
| `system(name = nil, &block)` | Creates a new system or retrieves an existing one by name |
| `tick(args)` | Updates all registered systems (called each frame) |
| `query(name = nil, &block)` | Creates a query to filter entities |
| `with(*components)` | Shorthand to create a query with specified components |
| `without(*components)` | Shorthand to create a query excluding specified components |
| `debug(bool = nil)` | Gets or sets debug mode |
| `<<(hash)` | Shorthand to create an entity with components defined in a hash |

### Entity

Container for components that represent a game object.

```ruby
world.entity do
  name :player
  as :player  # Access via world.player
  component :position, { x: 100, y: 100 }
  component :velocity, { x: 0, y: 0 }
end
```

#### Methods

| Method | Description |
|--------|-------------|
| `component(key, data = nil)` | Add a component or update component data |
| `add(...)` | Alias for component |
| `remove(key)` | Remove a component |
| `[](key)` | Get component data |
| `has_components?(mask)` | Check if entity has the specified component mask |
| `draw(&block)` | Define a custom draw function for the entity |

### System

Contains logic that processes entities with specific components.

```ruby
world.system do
  name :movement_system
  
  query do
    with :position, :velocity
  end
  
  callback do |entity|
    pos = entity.position
    vel = entity.velocity
    pos[:x] += vel[:x]
    pos[:y] += vel[:y]
  end
end
```

#### Methods

| Method | Description |
|--------|-------------|
| `query(&block)` | Define which entities this system should process |
| `callback(&block)` | Define the logic to execute on matching entities |
| `disable!` | Temporarily disable the system |
| `enable!` | Re-enable a disabled system |
| `disabled?` | Check if the system is disabled |

### Query

Filters entities based on component requirements.

```ruby
# Create a standalone query
query = world.query do
  with :position, :velocity
  without :static
end

# Process matching entities
query.each do |entity|
  # Process entity
end
```

#### Methods

| Method | Description |
|--------|-------------|
| `with(*components)` | Specify required components |
| `without(*components)` | Specify excluded components |
| `commit` | Finalize the query and build the entity cache |
| `each(&block)` | Iterate through matching entities |
| `to_a` | Get array of matching entities |
| `job(batch_size = 4, &block)` | Process entities in parallel batches |
| `raw(&block)` | Access the raw entity cache array |




## Debugging

```ruby
# Enable debug mode to see performance metrics
world.debug(true)

# Use benchmark utility
world.b("Operation label") do
  # Code to benchmark
end
```

## Example Usage

```ruby
game = Drecs.world do
  # Create systems
  system do
    name :movement
    query { with :position, :velocity }
    callback do |entity|
      entity.position[:x] += entity.velocity[:x]
      entity.position[:y] += entity.velocity[:y]
    end
  end
  
  system do
    name :render
    query { with :position, :sprite }
    callback do |entity|
      $args.outputs.sprites << {
        x: entity.position[:x],
        y: entity.position[:y],
        w: entity.sprite[:w],
        h: entity.sprite[:h],
        path: entity.sprite[:path]
      }
    end
  end
  
  # Create entities
  entity do
    name :player
    as :player
    component :position, { x: 100, y: 100 }
    component :velocity, { x: 1, y: 0 }
    component :sprite, { w: 32, h: 32, path: 'sprites/player.png' }
  end
end

def tick(args)
  # Update all systems
  game.tick(args)
end