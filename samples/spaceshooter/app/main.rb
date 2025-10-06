require_relative 'components/position.rb'
require_relative 'components/velocity.rb'
require_relative 'components/sprite.rb'
require_relative 'components/player.rb'
require_relative 'components/enemy.rb'
require_relative 'components/bullet.rb'
require_relative 'components/lifetime.rb'

require_relative 'systems/player_input_system.rb'
require_relative 'systems/movement_system.rb'
require_relative 'systems/enemy_ai_system.rb'
require_relative 'systems/lifetime_system.rb'
require_relative 'systems/collision_system.rb'
require_relative 'systems/render_system.rb'

def boot(args)
  args.state.world = Drecs::World.new

  args.state.world.spawn(
    Position.new(640, 100),
    Velocity.new(0, 0),
    Sprite.new(32, 32, 0, 200, 255),
    Player.new(5, 0)
  )

  10.times do |i|
    args.state.world.spawn(
      Position.new(100 + i * 100, 600),
      Velocity.new(2, 0),
      Sprite.new(32, 32, 255, 50, 50),
      Enemy.new(1)
    )
  end

  args.state.systems = [
    PlayerInputSystem.new,
    EnemyAISystem.new,
    MovementSystem.new,
    CollisionSystem.new,
    LifetimeSystem.new,
    RenderSystem.new
  ]
end

def tick(args)
  args.state.systems.each do |system|
    system.call(args.state.world, args)
  end

  args.outputs.labels << {
    x: 10,
    y: 710,
    text: "WASD/Arrow Keys to move, Space to shoot | FPS: #{args.gtk.current_framerate.to_i}",
    r: 255,
    g: 255,
    b: 255
  }
end
