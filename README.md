# Drecs

Drecs is a teeny tiny barebones ECS (Entity Component System) implementation for [DragonRuby](https://dragonruby.org/toolkit/game)

## Installation

While there's no formal package manager for DragonRuby, you can use clone the project into your `lib` folder to pull down the code into your project.

```
git clone https://github.com/joshleblanc/drecs.git lib/drecs
```

## Usage

Simply `require "lib/drecs/lib/drecs.rb"` at the top of your `main.rb`.

### Creating a World

The world is the central container for all entities, components, and queries.

```ruby
require 'lib/drecs/lib/drecs.rb'

# Create a world using a block
world = Drecs.world do
  # Optional: give your world a name
  name :game_world
  
  # Configure debug mode (default: false)
  debug true
end
```

### Creating and Managing Entities

Entities are containers for components. Each entity has a unique ID.

```ruby
# Create an entity with components
entity = world.entity do
  # Name the entity (optional)
  name :player
  
  # Make the entity accessible via world.player (optional)
  as :player
  
  # Add components directly
  component :position, { x: 100, y: 100 }
  component :velocity, { x: 0, y: 0 }
  component :size, { width: 32, height: 32 }

  # A no argument component is a tag
  component :friendly

  # Special helper that hooks directly into draw_override
  draw do |ffi_draw|
    ffi_draw.sprite(x: position.x, y: position.y, w: size.width, h: size.height)
  end
end

# Adding components later
entity.add_component(:health, amount: 100)

# Or using the shorthand
entity.add(:sprite, path: 'sprites/player.png')

# Removing components
entity.remove(:velocity)

# Accessing components
entity[:position] # => { x: 100, y: 100 }

# Components are also accessible as methods
entity.position # => { x: 100, y: 100 }

# Finding entities by name
player = world.entity(:player)
```

### Adding Entities Using Hash Syntax

You can also add entities using a hash syntax:

```ruby
# Add an entity with components in a single operation
world << {
  position: { x: 200, y: 200 },
  size: { width: 64, height: 64 },
  sprite: { path: 'sprites/enemy.png' },
  # A no argument component is a tag
  friendly: nil,
  # Special draw component that takes a block
  draw: ->(ffi_draw) {
    ffi_draw.sprite(x: 200, y: 200, w: 64, h: 64, path: 'sprites/enemy.png')
  }
}
```

### Querying Entities

Queries let you find entities with specific component combinations.

```ruby
# Query for entities with specific components
movables = world.with(:position, :velocity)

# Query for entities with some components but not others
enemies = world.with(:position, :ai).without(:friendly)

# More complex queries
query = world.query do
  with(:position, :sprite)
  without(:hidden)
  as :visible_sprites  # Makes the query accessible as world.visible_sprites
end

# Process query results
query.each do |entity|
  # Do something with each entity
  puts entity.position.x, entity.position.y
end

# Convert query results to array
entities_array = query.to_a

# Find a specific entity in query results
player = query.find { |e| e.name == :player }

# Get raw access to the entity cache
query.raw do |entities|
  # Direct access to the entity array
end

# Get the count of matching entities
query.count
```

### (WIP) Parallel Processing with Jobs

Process entities in parallel using the job system:

```ruby
# Process entities in parallel (4 at a time by default)
world.with(:physics).job do |entity|
  # This block runs in a separate thread for each entity
  update_physics(entity)
end

# Specify batch size
world.with(:ai).job(batch_size: 8) do |entity|
  # Process 8 entities concurrently
  update_ai(entity)
end
```

### Performance Measurement

```ruby
# Benchmark a block of code
world.b('Update physics') do
  # Code to benchmark
  update_physics_system()
end

# Benchmark with allocation tracking
world.b('Entity creation', allocations: true) do
  # Track memory allocations in this block
  create_many_entities()
end
```

## Development

Samples are available in the samples directory. We use [drakkon](https://gitlab.com/dragon-ruby/drakkon) to manage the DragonRuby version. With drakkon installed, use `drakkon run` to run the sample.

The drecs library is copied into the `lib` folder of the samples. You can create a Junction with the main lib folder on windows using `New-Item -ItemType Junction -Path lib -Target ..\..\lib` from within the sample app directory. This will let you modify drecs.rb in one place.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/drecs. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Drecs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).
