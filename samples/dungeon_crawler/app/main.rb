# Dungeon Crawler Sample - Grid-based dungeon crawler
# Run with: dragonruby . --sample dungeon_crawler

# ============================================================
# REQUIRE COMPONENTS
# ============================================================
require_relative 'components/tile.rb'
require_relative 'components/player_grid.rb'
require_relative 'components/position.rb'
require_relative 'components/velocity.rb'
require_relative 'components/health.rb'
require_relative 'components/enemy.rb'
require_relative 'components/events.rb'
require_relative 'components/sprite.rb'
require_relative 'components/destroyed.rb'
require_relative 'components/collider.rb'
require_relative 'components/item.rb'

# ============================================================
# REQUIRE SYSTEMS
# ============================================================
require_relative 'systems/dungeon_gen_system.rb'
require_relative 'systems/turn_system.rb'
require_relative 'systems/grid_movement_system.rb'
require_relative 'systems/player_attack_system.rb'
require_relative 'systems/damage_system.rb'
require_relative 'systems/death_system.rb'
require_relative 'systems/enemy_turn_system.rb'
require_relative 'systems/render_system.rb'
require_relative 'systems/pickup_system.rb'

# ============================================================
# GAME CONSTANTS
# ============================================================
TILE_SIZE = 32
DUNGEON_SIZE = 7  # 7x7 grid

# ============================================================
# BOOT / SETUP
# ============================================================
def boot(args)
  args.state.world = setup_world(args)
  setup_schedule(args.state.world)
end

def setup_world(args)
  world = Drecs::World.new

  # ============================================================
  # RESOURCES - Turn state management
  # ============================================================
  world.insert_resource(:turn_state, {
    phase: :player_input,
    player_acted: false,
    enemy_acted: false
  })

  world.insert_resource(:game_state, {
    game_over: false,
    score: 0
  })

  # ============================================================
  # SPAWN PLAYER at center of 7x7 grid
  # ============================================================
  player_id = world.spawn(
    PlayerGrid.new(3, 3, :down),
    Health.new(10, 10)
  )
  world.name(player_id, "Player")

  # ============================================================
  # DUNGEON GENERATION - Creates dungeon and spawns goblins
  # ============================================================
  DungeonGenSystem.generate_dungeon(world)

  world
end

def setup_schedule(world)
  world.clear_schedule!

  # Turn system runs first
  world.add_system(:turn, system: TurnSystem.new)

  # Grid movement - only during player input phase
  world.add_system(:grid_movement, if: ->(w, _a) {
    w.resource(:turn_state)[:phase] == :player_input && !w.resource(:game_state)[:game_over]
  }, system: GridMovementSystem.new)

  # Player attack - during player input phase
  world.add_system(:player_attack, if: ->(w, _a) {
    w.resource(:turn_state)[:phase] == :player_input && !w.resource(:game_state)[:game_over]
  }, system: PlayerAttackSystem.new)

  # Pickup items - Space to pick up
  world.add_system(:pickup, if: ->(w, _a) {
    w.resource(:turn_state)[:phase] == :player_input && !w.resource(:game_state)[:game_over]
  }, system: PickupSystem.new)

  # Damage processing
  world.add_system(:damage, system: DamageSystem.new)

  # Death/Game over check
  world.add_system(:death, system: DeathSystem.new)

  # Enemy turn - after player acts
  world.add_system(:enemy_turn, if: ->(w, _a) {
    w.resource(:turn_state)[:phase] == :enemy_turn && !w.resource(:game_state)[:game_over]
  }, system: EnemyTurnSystem.new)

  # Render
  world.add_system(:render, system: RenderSystem.new)
end

# ============================================================
# MAIN TICK
# ============================================================
def tick(args)
  boot(args) unless args.state.world

  if args.inputs.keyboard.key_down.r
    args.state.world = setup_world(args)
    setup_schedule(args.state.world)
  end

  args.state.world.tick(args)
end