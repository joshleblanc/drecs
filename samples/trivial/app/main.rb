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
    args.state.entities.query(Position, Velocity) do |positions, velocities|
       positions.each_with_index do |pos, i|
           pos.x += velocities[i].dx
           pos.y += velocities[i].dy
       end 
    end

    puts "--- Tick Report ---"
    args.state.entities.query(Position, Tag) do |positions, tags|
        positions.each_with_index do |pos, i|
            tag = tags[i]
            puts "#{tag.name} is at #{pos.x.round(2)}, #{pos.y.round(2)}"
        end
    end
    puts "-------------------"

    if args.state.tick_count == 1
        args.state.entities.add_component(
            args.state.tree,
            Velocity.new(-5, 0)
        )
    end
end