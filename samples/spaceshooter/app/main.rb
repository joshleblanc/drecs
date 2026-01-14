require_relative 'components/position.rb'
require_relative 'components/velocity.rb'
require_relative 'components/sprite.rb'
require_relative 'components/player.rb'
require_relative 'components/enemy.rb'
require_relative 'components/bullet.rb'
require_relative 'components/lifetime.rb'
require_relative 'components/hit_event.rb'

require_relative 'systems/player_input_system.rb'
require_relative 'systems/movement_system.rb'
require_relative 'systems/enemy_ai_system.rb'
require_relative 'systems/lifetime_system.rb'
require_relative 'systems/collision_system.rb'
require_relative 'systems/hit_event_system.rb'
require_relative 'systems/render_system.rb'

PLAYER_BUNDLE = Drecs.bundle(Position, Velocity, Sprite, Player)
ENEMY_BUNDLE = Drecs.bundle(Position, Velocity, Sprite, Enemy)

def boot(args)
  args.state.world = Drecs::World.new

  args.state.world.spawn_bundle(PLAYER_BUNDLE,
    Position.new(640, 100),
    Velocity.new(0, 0),
    Sprite.new(32, 32, 0, 200, 255),
    Player.new(5, 0)
  )

  10.times do |i|
    args.state.world.spawn_bundle(ENEMY_BUNDLE,
      Position.new(100 + i * 100, 600),
      Velocity.new(2, 0),
      Sprite.new(32, 32, 255, 50, 50),
      Enemy.new(1)
    )
  end

  world = args.state.world
  world.clear_schedule!
  world.add_system(:input, system: PlayerInputSystem.new)
  world.add_system(:enemy_ai, after: :input, system: EnemyAISystem.new)
  world.add_system(:movement, after: :enemy_ai, system: MovementSystem.new)
  world.add_system(:collision, after: :movement, system: CollisionSystem.new)
  world.add_system(:hit_events, after: :collision, system: HitEventSystem.new)
  world.add_system(:lifetime, after: :hit_events, system: LifetimeSystem.new)
  world.add_system(:render, after: :lifetime, system: RenderSystem.new)
end

def tick(args)
  boot(args) unless args.state.world
  args.state.world.tick(args)

  args.outputs.labels << {
    x: 10,
    y: 710,
    text: "WASD/Arrow Keys to move, Space to shoot | FPS: #{args.gtk.current_framerate.to_i}",
    r: 255,
    g: 255,
    b: 255
  }
end
