def boot(args)
  world = ecs_init
  bob = ecs_set_name world, 0, "Bob"
  
  p world
end

def tick(args)
  
end