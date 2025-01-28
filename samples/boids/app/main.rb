include Drecs::Main

RESOLUTION = {
  w: 1280,
  h: 720
}

BOIDS_COUNT = 10

SEPARATION_WEIGHT = 20
ALIGNMENT_WEIGHT = 4 
COHESION_WEIGHT = 1

NEIGHBOUR_RANGE = 0
MIN_VELOCITY = 290
MAX_VELOCITY = 300


component :position, x: 0, y: 0
component :size, w: 0, h: 0
component :color, r: 0, g: 0, b: 0, a: 255
component :acceleration, value: 0
component :behavior, center: { x: 0, y: 0 }, direction: { x: 0, y: 0 }, count: 0
component :velocity, x: 0, y: 0

system :destination, :position do |entities|
  entities.each do |entity|
    destination = { x: 0, y: 0 }

    entities.each do |other|
      next if entity == other

      destination = vec2_add(destination, other.position)
    end

    destination = vec2_div(destination, entities.count - 1) 

    velocity = vec2_sub(destination, entity.position)
    velocity = vec2_div(velocity, 100)

    add_component entity, :velocity, vec2_add(entity.velocity, velocity)
  end
end

system :shy, :position do |entities|
  entities.each do |entity|
    count = { x: 0, y: 0 }

    entities.each do |other|
      next if entity == other
      next unless Geometry.vec2_magnitude(vec2_sub(entity.position, other.position)) < NEIGHBOUR_RANGE

      count = vec2_sub(count, vec2_sub(entity.position, other.position))
    end

    add_component entity, :velocity, vec2_add(entity.velocity, count)
  end
end

system :insecure, :position do |entities|
  entities.each do |entity|
    vel = { x: 0, y: 0 }

    entities.each do |other|
      next if entity == other

      vel = vec2_add(vel, other.velocity)
    end

    vel = vec2_div(vel, entities.count - 1)

    add_component entity, :velocity, vec2_div(vec2_sub(vel, entity.velocity), 8)
  end
end

system :position, :velocity, :position do |entities|
  entities.each do |entity|
    add_component entity, :position, vec2_add(entity.position, entity.velocity)
  end
end

system :draw, :position, :size, :color do |entities|
  entities.each do |entity|
    outputs.solids << {
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

world :default, systems: [:destination, :insecure, :position,:draw]

def setup 
  set_world :default
  BOIDS_COUNT.times do 
    create_boid
  end
end

def tick(args)
  setup if args.tick_count == 0 

  process_systems(args)
end