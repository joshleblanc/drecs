Position = Struct.new(:x, :y)
Velocity = Struct.new(:dx, :dy)
Tag = Struct.new(:name)

# Define resources
GameTime = Struct.new(:elapsed, :delta)
GameConfig = Struct.new(:simulation_speed, :show_debug)

def boot(args)
    args.state.entities = Drecs::World.new

    # Insert resources
    args.state.entities.insert_resource(GameTime.new(0.0, 0.016))
    args.state.entities.insert_resource(GameConfig.new(1.0, true))

    args.state.entities.spawn(
        Position.new(10, 20),
        Velocity.new(1, 0.5),
        Tag.new("Player")
    )

    args.state.tree = args.state.entities.spawn(
        Position.new(100, 100),
        Tag.new("Tree")
    )
end

def tick(args)
    args.state.entities.advance_change_tick!

    # Get resources
    time = args.state.entities.resource(GameTime)
    config = args.state.entities.resource(GameConfig)

    # Update time resource
    time.elapsed += time.delta * config.simulation_speed

    # Update all entities with velocity
    args.state.entities.each_entity(Position, Velocity) do |entity_id, pos, vel|
        pos.x += vel.dx * config.simulation_speed
        pos.y += vel.dy * config.simulation_speed
    end

    if args.state.tick_count == 1
        # Add velocity to the tree using the new API
        if args.state.entities.add_component(args.state.tree, Velocity.new(-5, 0))
            puts "Tree now has velocity!"
        end
    end

    if config.show_debug
        puts "--- Tick Report ---"
        puts "Time: #{time.elapsed.round(2)}s | Speed: #{config.simulation_speed}x"
        args.state.entities.each_entity(Position, Tag) do |entity_id, pos, tag|
            puts "#{tag.name} is at #{pos.x.round(2)}, #{pos.y.round(2)}"
        end
        puts "Velocity changed this tick: #{args.state.entities.count(Velocity, changed: [Velocity])}"
        puts "Entity count: #{args.state.entities.entity_count}"
        puts "Archetype count: #{args.state.entities.archetype_count}"
        puts "-------------------"
    end
end