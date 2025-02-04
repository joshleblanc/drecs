class World 
  def initialize
    @flecs_world = FFI::Flecs.ecs_init
  end

  def entity 
    FFI::Flecs.ecs_new(@flecs_world)
  end

  def scope 
    FFI::Flecs.ecs_get_scope(@flecs_world)
  end
end

def boot(args)
  world = World.new
  p world.entity
  p world.scope
end

def tick(args)
  
end