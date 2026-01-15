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

    world = args.state.entities
    world.clear_schedule!

    args.state.hook_velocity_added = 0
    args.state.hook_tag_added = 0

    world.on_added(Velocity) { |_w, _id, _c| args.state.hook_velocity_added += 1 }
    world.on_added(Tag) { |_w, _id, _c| args.state.hook_tag_added += 1 }

    world.add_system(:time) do |w, _a|
        time = w.resource(GameTime)
        config = w.resource(GameConfig)
        time.elapsed += time.delta * config.simulation_speed
    end

    world.add_system(:movement, after: :time) do |w, _a|
        config = w.resource(GameConfig)
        w.each_entity(Position, Velocity) do |_entity_id, pos, vel|
            pos.x += vel.dx * config.simulation_speed
            pos.y += vel.dy * config.simulation_speed
        end
    end

    world.add_system(:tree_velocity, after: :movement) do |w, a|
        if a.state.tick_count == 1
            if w.add_component(a.state.tree, Velocity.new(-5, 0))
                puts "Tree now has velocity!"
            end
        end
    end

    world.add_system(:debug, after: :tree_velocity, if: ->(w, _a) { (cfg = w.resource(GameConfig)) && cfg.show_debug }) do |w, a|
        time = w.resource(GameTime)
        config = w.resource(GameConfig)

        puts "--- Tick Report ---"
        puts "Time: #{time.elapsed.round(2)}s | Speed: #{config.simulation_speed}x"
        puts "Hooks: Velocity added #{a.state.hook_velocity_added}, Tags added #{a.state.hook_tag_added}"
        w.each_entity(Position, Tag) do |_entity_id, pos, tag|
            puts "#{tag.name} is at #{pos.x.round(2)}, #{pos.y.round(2)}"
        end
        puts "Velocity changed this tick: #{w.count(Velocity, changed: [Velocity])}"
        puts "Entity count: #{w.entity_count}"
        puts "Archetype count: #{w.archetype_count}"
        puts "-------------------"
    end
end

def tick(args)
    boot(args) unless args.state.entities
    args.state.entities.tick(args)
end