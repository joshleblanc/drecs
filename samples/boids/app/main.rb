include Drecs::Main

RESOLUTION = {
  w: 1280,
  h: 720
}

BOIDS_COUNT = 100

SEPARATION_WEIGHT = 20
ALIGNMENT_WEIGHT = 4 
COHESION_WEIGHT = 1

MOVEMENT_ACCURACY = 2 

NEIGHBOUR_RANGE = 75
MIN_VELOCITY = 5
MAX_VELOCITY = 10

component :position, x: 0, y: 0
component :size, w: 0, h: 0
component :color, r: 0, g: 0, b: 0, a: 255
component :acceleration, value: 0
component :behavior, center: { x: 0, y: 0 }, direction: { x: 0, y: 0 }, count: 0
component :velocity, x: 0, y: 0

def neighbours(entity, entities) 
  n = Array.filter_map(entities) do |other|
    next if entity == other
    distance = Geometry.vec2_magnitude(vec2_sub(entity.position, other.position))
    next if distance >= NEIGHBOUR_RANGE * 2
    [other, distance]
  end
  n.sort_by { |_, dist| dist }.first(MOVEMENT_ACCURACY)
end

def destination(entity, entities)
  d = { x: 0, y: 0 }
  
  neighbors = neighbours(entity, entities)
  
  return entity.velocity if neighbors.empty?
  
  Array.each(neighbors) do |other, _|
    d = vec2_add(d, other.position)
  end
  
  d = vec2_div(d, neighbors.length)
  velocity = vec2_sub(d, entity.position)
  velocity = vec2_div(velocity, 100)

  vec2_add(entity.velocity, velocity)
end

def shy(entity, entities)
  separation = { x: 0, y: 0 }
  
  neighbors = neighbours(entity, entities)
  
  return entity.velocity if neighbors.empty?
  
  Array.each(neighbors) do |other, magnitude|
    distance = vec2_sub(entity.position, other.position)
    if magnitude > 0
      distance = vec2_div(distance, magnitude * magnitude)
    end
    separation = vec2_add(separation, distance)
  end
  
  separation = vec2_div(separation, neighbors.length)
  separation = vec2_mul(separation, 2.0)
  
  vec2_add(entity.velocity, separation)
end

def insecure(entity, entities)
  vel = { x: 0, y: 0 }
  
  neighbors = neighbours(entity, entities)
  
  return entity.velocity if neighbors.empty?
  
  Array.each(neighbors) do |other, _|
    vel = vec2_add(vel, other.velocity)
  end
  
  vel = vec2_div(vel, neighbors.length)
  vec2_div(vec2_sub(vel, entity.velocity), 4)
end


system :velocity, :position, :velocity do |entities|
  Array.each(entities) do |entity|
    b "cohesion" do 
      cohesion = vec2_mul(destination(entity, entities), COHESION_WEIGHT)
    end
    b "separation" do
      separation = vec2_mul(shy(entity, entities), SEPARATION_WEIGHT)
    end

    b "alignment" do 
      alignment = vec2_mul(insecure(entity, entities), ALIGNMENT_WEIGHT)
    end

    velocity = vec2_add(vec2_add(cohesion, separation), alignment)
    add_component entity, :velocity, velocity
  end
end

system :constrain_velocity, :velocity do |entities|
  Array.each(entities) do |entity|
    magnitude = Geometry.vec2_magnitude(entity.velocity)
    
    if magnitude < MIN_VELOCITY
      scale = MIN_VELOCITY / magnitude
      add_component entity, :velocity, vec2_mul(entity.velocity, scale)
    elsif magnitude > MAX_VELOCITY
      scale = MAX_VELOCITY / magnitude
      add_component entity, :velocity, vec2_mul(entity.velocity, scale)
    end
  end
end

system :position, :velocity, :position do |entities|
  Array.each(entities) do |entity|
    add_component entity, :position, vec2_add(entity.position, entity.velocity)
  end   
end

system :screen_bounds, :position do |entities|
  Array.each(entities) do |entity|
    x = entity.position.x
    y = entity.position.y
    
    x = RESOLUTION[:w] if x < 0
    x = 0 if x > RESOLUTION[:w]
    
    y = RESOLUTION[:h] if y < 0
    y = 0 if y > RESOLUTION[:h]
    
    if x != entity.position.x || y != entity.position.y
      add_component entity, :position, { x: x, y: y }
    end
  end
end

system :draw, :position, :size, :color do |entities|
  outputs.solids << Array.map(entities) do |entity|
    {
      x: entity.position.x,
      y: entity.position.y,
      w: entity.size.w,
      h: entity.size.h,
      r: entity.color.r,
      g: entity.color.g,
      b: entity.color.b,
      a: entity.color.a
    } 
  end
end

def vec2_div(a, b)
  { x: a.x / b, y: a.y / b }
end

def vec2_mul(a, b)
  { x: a.x * b, y: a.y * b }
end

def vec2_sub(a, b)
  { x: a.x - b.x, y: a.y - b.y }
end

def vec2_add(a, b)
  { x: a.x + b.x, y: a.y + b.y }
end


def create_boid
  boid = create_entity(:boid)
  add_component(boid, :position, x: rand * RESOLUTION.w, y: rand * RESOLUTION.h)
  add_component(boid, :size, w: Numeric.rand(10..15), h: Numeric.rand(20..30))
  add_component(boid, :color, r: rand(255), g: rand(255), b: rand(255), a: 255)

  velocity = Geometry.vec2_normalize({ x: rand - 0.5, y: rand - 0.5 })
  operand = (MIN_VELOCITY + (rand * (MAX_VELOCITY - MIN_VELOCITY)))
  velocity = {
    x: velocity.x * operand,
    y: velocity.y * operand
  }
  add_component(boid, :velocity, value: velocity)

  boid
end

world :default, systems: [:velocity, :constrain_velocity, :position, :screen_bounds, :draw]

def boot(args)
  set_world :default
  BOIDS_COUNT.times do 
    create_boid
  end
end

def tick(args)
  process_systems(args, debug: true)

  args.outputs.debug << "#{args.gtk.current_framerate} fps"
  args.outputs.debug << "#{args.gtk.current_framerate_calc} fps simulation"
  args.outputs.debug << "#{args.gtk.current_framerate_render} fps render"
end