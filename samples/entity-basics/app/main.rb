# include FFI::FLECS

# Position = FFI::Struct.new(:x, :y)

class Component < FFI::Struct
  attr_reader :desc, :entity
  def initialize(**args)
    @desc = FFI::FLECS::Ecs_component_desc_t.new
    @desc.type.size = self.size
    @desc.type.alignment = self.alignment
  end
end

class Position < Component 
  layout :x, :double
         :y, :double
  
end

class Walking < Component; end 

class World 
  def initialize 
    @ecs_world = FFI::FLECS.ecs_init
  end

  def entity(name = nil)
    entity = Entity.new(world: self, name: name)
  end
end

class Entity 
  def initialize(world:, name: nil) 
    @world = world
    @name = name
    @ecs_entity = FFI::FLECS.ecs_new(world)
  end

  def set(component)
    component.desc.entity = @ecs_entity
    component.entity = self
  end

  def get(component)
    FFI::FLECS.ecs_get(@world, @ecs_entity, component.desc)
  end
end

# def tick(args)
#   # Initialize the world if not already done
#   unless world

    world = World.new 
    bob = world.entity("Bob")
    bob.set(Position.new(10, 20)).
    bob.add(Walking.new)
    world = FFI::FLECS.ecs_mini()
    
    desc = FFI::FLECS::Ecs_component_desc_t.new
    desc.entity = FFI::FLECS.ecs_new(world)
    desc.type.size = Position.size
    desc.type.alignment = Position.alignment
    position_id = FFI::FLECS.ecs_component_init(world, desc)
    
#     # Create the Walking tag
#     walking_id = FFI::FLECS.ecs_entity_init(world, FFI::FLECS::Ecs_entity_desc_t.new)
    
#     # Create entity with name Bob
#     bob = FFI::FLECS.ecs_set_name(world, 0, "Bob")
    
#     # Set position for Bob
#     pos = Position.new
#     pos[:x] = 10.0
#     pos[:y] = 20.0
#     FFI::FLECS.ecs_set_ptr(world, bob, position_id, pos)
    
#     # Add Walking tag to Bob
#     FFI::FLECS.ecs_add_id(world, bob, walking_id)
    
#     # Get position for Bob
#     ptr = FFI::FLECS.ecs_get_ptr(world, bob, position_id)
#     if ptr
#       pos = Position.new(ptr)
#       puts "{#{pos[:x]}, #{pos[:y]}}"
#     end
    
#     # Update Bob's position
#     pos = Position.new
#     pos[:x] = 20.0
#     pos[:y] = 30.0
#     FFI::FLECS.ecs_set_ptr(world, bob, position_id, pos)
    
#     # Create Alice
#     @alice = FFI::FLECS.ecs_set_name(world, 0, "Alice")
#     pos = Position.new
#     pos[:x] = 10.0
#     pos[:y] = 20.0
#     FFI::FLECS.ecs_set_ptr(world, @alice, position_id, pos)
#     FFI::FLECS.ecs_add_id(world, @alice, walking_id)
    
#     # Print components
#     type_str = FFI::FLECS.ecs_type_str(world, FFI::FLECS.ecs_get_type(world, @alice))
#     puts "[#{type_str}]"
#     FFI::FLECS.ecs_os_free(type_str)
    
#     # Remove Walking tag from Alice
#     FFI::FLECS.ecs_remove_id(world, @alice, walking_id)
#   end
  
#   # Iterate entities with Position
#   it = FFI::FLECS.ecs_each(world, position_id)
#   while FFI::FLECS.ecs_each_next(it) != 0
#     pos = Position.new(FFI::FLECS.ecs_field_ptr(it, 0))
#     count = it[:count]
#     count.times do |i|
#       entity = it[:entities][i]
#       name = FFI::FLECS.ecs_get_name(world, entity)
#       puts "#{name}: {#{pos[:x]}, #{pos[:y]}}"
#     end
#   end
# end