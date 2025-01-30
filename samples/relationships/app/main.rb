def boot(args) 
  world = Drecs.world
  args.state.world = world

  apples = world.entity
  pears = world.entity

  world.entity do 
    name :bob
    component :position, x: 10, y: 10
    component :test
    relationship :eats, apples
    relationship :eats, pears
  end
end

def tick(args)
  args.state.world.tick(args)

  p args.state.world.query { where(eats: apples) }.count
  p args.state.world.query { where(test: { x: 5 }) }.count
end