# Drecs

Drecs is a teeny tiny barebones ecs implementation for [DragonRuby](https://dragonruby.org/toolkit/game)

## Installation

While there's no formal package manager for DragonRuby, you can use `$gtk.download_stb_rb("https://github.com/joshleblanc/drecs/blob/master/lib/drecs.rb")` to pull down the code into your project.

## Usage

Simply `require "joshleblanc/drecs/drecs.rb"` at the top of your `main.rb`.

There are two ways of including Drecs in your project

* If you're not using a Game class, use `include Drecs::Main` to include everything at the top level
* If you're using a Game class, use `include Drecs` in the class to include the appropriate class/instance methods

### Creating components

Use the class method `component(name, **defaults)` to create components

```ruby 
component :exploded
component :position, { x: 0, y: 0}
component :size, { w: 0, h: 0}
component :sprite, { path: nil },
component :health, { amt: 100 }
```

### Creating entities

Use the class method `entity(name, *components)` to create entities

```ruby
entity :barrel, :health, :position, :size, :sprite
```

### Creating systems

Use the class method `system(name, *filters, &blk)` to create systems

System blocks are run within the `args` context. All top level `args` accessors are available to you, such as `state`, `outputs`, `inputs`, etc.

```ruby
system :render_sprites, :position, :size, :sprite do |entities| 
    outputs.sprites << entities.map |e|
        {
            x: e.position.x,
            y: e.position.y,
            w: e.size.w,
            h: e.size.h,
            path: e.sprite.path
        }
    end
end

system :handle_death, :health do |entities|
    entities.select { |e| e.health.amt <= 0 }.each do |e|
        add_component(e, :exploded)
    end
end
```

### Creating worlds

Use the class method `world(name, components: [], systems: [])` to create worlds

```ruby
world(:game, entities: [:barrel], systems: [:handle_death, :render_sprites])
```

### Utilities

The following are utilities available at the instance level

`set_world(world)` is used to activate a world. This will populate the world with the default systems and entities defined on the world

```ruby 
def defaults(args)
    return unless args.state.tick_count == 0

    set_world(:game)
end

def tick(args)
    defaults(args)
    process_systems(args)
end
```

`process_systems(args)` is used to run the game - this should be called from the tick method

```ruby 
def tick(args)
    process_systems(args)
end
```

`add_component(entity, component)` is used to add a component to an entity

`remove_component(entity, component)` is used to remove a component from an entity

`has_components?(entity, *components)` will return true if the entity contains all of the provided components

`create_entity(entity_type, **overrides)` will create an entity of the specified type, merging the overrides with the defaults. The created entity entity will automatically be added to `state.entities`. If the `:as` override is provided, the entity will also be added to `state` directly.

```ruby
system :example do 
    create_entity(:barrel, as: :primary)

    state.entities.select { |e| e.entity_type == :barrel }.count # => 1
    state.primary # => the barrel
end
```

`delete_entity(entity)` will delete the entity from `state.entities`, as well as remove the alias from `state`, if applicable

`add_system(system)` will add a system to the currently active world

`remove_system(system)` will remove a system from the currently active world

## Development

Samples are available in the samples directory. We use [drakkon](https://gitlab.com/dragon-ruby/drakkon) to manage the DragonRuby version. With drakkon installed, use `drakkon run` to run the sample.

The drecs library is copied into the `lib` folder of the samples. You can create a Junction with the main lib folder on windows using `New-Item -ItemType Junction -Path lib -Target ..\..\lib` from within the sample app directory. This will let you modify drecs.rb in one place.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/drecs. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Drecs project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/drecs/blob/master/CODE_OF_CONDUCT.md).
