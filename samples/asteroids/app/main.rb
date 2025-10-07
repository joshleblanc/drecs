require_relative 'components/position.rb'
require_relative 'components/velocity.rb'
require_relative 'components/rotation.rb'
require_relative 'components/sprite.rb'
require_relative 'components/polygon.rb'
require_relative 'components/collider.rb'
require_relative 'components/tags.rb'

require_relative 'systems/player_input_system.rb'
require_relative 'systems/movement_system.rb'
require_relative 'systems/bullet_system.rb'
require_relative 'systems/collision_system.rb'
require_relative 'systems/render_system.rb'

def tick(args)
  args.state.world ||= setup_world(args)
  args.state.systems ||= setup_systems

  if args.state.game_over
    if args.inputs.keyboard.key_down.r
      args.state.world = setup_world(args)
      args.state.game_over = false
    end
  else
    args.state.systems.each { |system| system.call(args.state.world, args) }
  end

  args.state.systems.last.call(args.state.world, args)
end

def setup_world(args)
  world = Drecs::World.new

  ship_points = [
    [15, 0],
    [-10, -10],
    [-5, 0],
    [-10, 10]
  ]

  world.spawn(
    Position.new(640, 360),
    Velocity.new(0, 0),
    Rotation.new(0, 0),
    Player.new(0.3, 5),
    Collider.new(10),
    Polygon.new(ship_points, 100, 200, 255)
  )

  5.times do
    spawn_asteroid(world, 3)
  end

  args.state.score = 0

  world
end

def spawn_asteroid(world, size)
  x = rand(1280)
  y = rand(720)

  angle = rand(360) * Math::PI / 180
  speed = 0.5 + rand(1.5)

  world.spawn(
    Position.new(x, y),
    Velocity.new(Math.cos(angle) * speed, Math.sin(angle) * speed),
    Rotation.new(rand(360), Numeric.rand(-2.0..2.0)),
    Asteroid.new(size),
    Collider.new(10 * size),
    Polygon.new(
      generate_asteroid_points(size),
      200, 200, 200
    )
  )
end

def generate_asteroid_points(size)
  radius = 10 * size
  num_points = 8
  points = []

  num_points.times do |i|
    angle = (i / num_points.to_f) * 2 * Math::PI
    r = radius + Numeric.rand(-radius * 0.3..radius * 0.3)
    points << [Math.cos(angle) * r, Math.sin(angle) * r]
  end

  points
end

def setup_systems
  [
    PlayerInputSystem.new,
    MovementSystem.new,
    BulletSystem.new,
    CollisionSystem.new,
    RenderSystem.new
  ]
end
