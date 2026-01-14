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
  setup_schedule(args) unless args.state.schedule_initialized

  if args.state.game_over
    if args.inputs.keyboard.key_down.r
      args.state.world = setup_world(args)
      args.state.game_over = false
      args.state.schedule_initialized = false
      setup_schedule(args)
    end
  end

  args.state.world.tick(args)
end

def setup_schedule(args)
  world = args.state.world
  world.clear_schedule!

  run_sim = ->(_w, a) { !a.state.game_over }

  world.add_system(:input, if: run_sim, system: PlayerInputSystem.new)
  world.add_system(:movement, after: :input, if: run_sim, system: MovementSystem.new)
  world.add_system(:bullets, after: :movement, if: run_sim, system: BulletSystem.new)
  world.add_system(:collision, after: :bullets, if: run_sim, system: CollisionSystem.new)
  world.add_system(:render, after: :collision, system: RenderSystem.new)

  args.state.schedule_initialized = true
  nil
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
  args.state.game_over = false

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
