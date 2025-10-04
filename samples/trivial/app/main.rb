Position = Struct.new(:x, :y)
Velocity = Struct.new(:dx, :dy)
Tag = Struct.new(:name)

def boot(args)
    args.state.entities = Drecs::World.new

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
    # Update all entities with velocity
    args.state.entities.each_entity(Position, Velocity) do |entity_id, pos, vel|
        pos.x += vel.dx
        pos.y += vel.dy
    end

    puts "--- Tick Report ---"
    args.state.entities.each_entity(Position, Tag) do |entity_id, pos, tag|
        puts "#{tag.name} is at #{pos.x.round(2)}, #{pos.y.round(2)}"
    end
    puts "Entity count: #{args.state.entities.entity_count}"
    puts "Archetype count: #{args.state.entities.archetype_count}"
    puts "-------------------"

    if args.state.tick_count == 1
        # Add velocity to the tree using the new API
        if args.state.entities.add_component(args.state.tree, Velocity.new(-5, 0))
            puts "Tree now has velocity!"
        end
    end
end