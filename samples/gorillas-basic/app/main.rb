require 'lib/drecs'

# Game constants
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
FANCY_WHITE = { r: 255, g: 255, b: 255 }.freeze

def tick(args)
  # Run systems in order
  # First run the generate_stage system only once
  if args.state.tick_count === 0
    generate_stage(args)
  end
  
  # Then run all other systems every frame
  handle_input(args)
  handle_rotation(args)
  update_physics(args)
  handle_collisions(args)
  handle_explosions(args)
  check_win(args)
  
  # Rendering systems
  render_background(args)
  render_buildings(args)
  render_sprites(args)
  render_ui(args)
  
  # Cleanup at the end
  cleanup_ephemeral(args)
end

# Create the game world
def boot(args)
  world = Drecs.world
  
  # Set up queries for specific component combinations
  world.query do
    with(:position, :rendered)
    as :renderables
  end
  
  world.query do
    with(:position, :solid)
    as :solids
  end
  
  world.query do
    with(:position, :solid, :building)
    as :buildings
  end
  
  world.query do
    with(:position, :velocity, :collides)
    as :projectiles
  end
  
  world.query do
    with(:position, :killable)
    as :killables
  end
  
  world.query do
    with(:ephemeral)
    as :ephemerals
  end
  
  world.query do
    with(:score)
    as :scorekeepers
  end
  
  # Create the background
  world.entity do
    component :background_color, {r: 41, g: 44, b: 53}
  end
  
  # Create the wind entity
  world.entity do
    name :wind
    as :wind
    component :speed, (rand * 4) - 2  # Random wind between -2 and 2
  end
  
  # Create the gravity entity
  world.entity do
    name :gravity
    as :gravity
    component :speed, 0.1  # Gravity strength
  end
  
  # Create the current turn entity
  world.entity do
    name :current_turn
    as :current_turn
    component :turn, {
      angle: "",
      velocity: "",
      angle_committed: false,
      velocity_committed: false,
      current_player: 1,  # Start with player 1
      first_player: 1
    }
  end
  
  # Create player 1 (left gorilla)
  world.entity do
    name :player_one
    as :player_one
    component :position, {x: 100, y: 200}
    component :size, {width: 50, height: 50}
    component :solid, true
    component :killable, true
    component :rendered, true
    component :score, 0
    component :player, 1
    component :sprite, {path: 'sprites/gorilla.png'}
    component :explodes, false
  end
  
  # Create player 2 (right gorilla)
  world.entity do
    name :player_two
    as :player_two
    component :position, {x: 1180, y: 200}
    component :size, {width: 50, height: 50}
    component :solid, true
    component :killable, true
    component :rendered, true
    component :score, 0
    component :player, 2
    component :sprite, {path: 'sprites/gorilla.png'}
    component :explodes, false
  end
  
  # Flag to run generate_stage only once
  args.state.generate_stage = true
  
  args.state.world = world
end

# System: Generate the game stage
def generate_stage(args)
  world = args.state.world
  # Clear any existing buildings
  world.buildings.each do |entity|
    world.entities.delete(entity)
  end
  
  # Create ground
  world.entity do
    component :position, {x: 0, y: 0}
    component :size, {width: SCREEN_WIDTH, height: 100}
    component :solid, true
    component :building, true
    component :rendered, true
    component :sprite, {path: :pixel, r: 100, g: 100, b: 100}
  end
  
  # Generate buildings with random heights
  building_width = 100
  gap = 50
  ground_y = 100
  
  # Create left buildings
  left_buildings = []
  (0..2).each do |i|
    height = Numeric.rand(100..300)
    x_pos = i * (building_width + gap)
    
    # Create building entity
    building = world.entity do
      component :position, {x: x_pos, y: ground_y}
      component :size, {width: building_width, height: height}
      component :solid, true
      component :building, true
      component :rendered, true
      component :sprite, {path: :pixel, r: 100, g: 100, b: 100}
    end
    
    left_buildings << building
    
    # Add windows to building
    add_windows_to_building(world, x_pos, ground_y, building_width, height)
  end
  
  # Create right buildings
  right_buildings = []
  (7..9).each do |i|
    height = Numeric.rand(100..300)
    x_pos = i * (building_width + gap)
    
    # Create building entity
    building = world.entity do
      component :position, {x: x_pos, y: ground_y}
      component :size, {width: building_width, height: height}
      component :solid, true
      component :building, true
      component :rendered, true
      component :sprite, {path: :pixel, r: 100, g: 100, b: 100}
    end
    
    right_buildings << building
    
    # Add windows to building
    add_windows_to_building(world, x_pos, ground_y, building_width, height)
  end
  
  # Position players on buildings
  position_players_on_buildings(world, left_buildings.first, right_buildings.last)
  
  # Set random wind
  wind = world.wind
  wind.speed = (rand * 4) - 2 if wind
  
  # Reset turn state
  turn = world.current_turn
  if turn && turn.turn
    turn.turn.angle = ""
    turn.turn.velocity = ""
    turn.turn.angle_committed = false
    turn.turn.velocity_committed = false
  end
  
  # No need to remove the system - we control when it runs in tick method
end

# Helper function to add windows to buildings
def add_windows_to_building(world, x, y, width, height)
  window_size = 15
  window_gap = 5
  windows_x = x + window_gap
  windows_y = y + window_gap
  max_windows_x = (width - window_gap) / (window_size + window_gap)
  max_windows_y = (height - window_gap) / (window_size + window_gap)
  
  (0...max_windows_x.to_i).each do |wx|
    (0...max_windows_y.to_i).each do |wy|
      next if rand > 0.7  # Randomly skip some windows
      
      # Create window entity
      world.entity do
        component :position, {
          x: windows_x + wx * (window_size + window_gap),
          y: windows_y + wy * (window_size + window_gap)
        }
        component :size, {width: window_size, height: window_size}
        component :rendered, true
        component :sprite, {path: :pixel, r: 200, g: 200, b: 0}
      end
    end
  end
end

# Position players on the left and right buildings
def position_players_on_buildings(world, left_building, right_building)
  # Position player one on left building
  player_one = world.player_one
  if left_building && player_one
    player_one.position.x = left_building.position.x + left_building.size.width / 2 - player_one.size.width / 2
    player_one.position.y = left_building.position.y + left_building.size.height
  end
  
  # Position player two on right building
  player_two = world.player_two
  if right_building && player_two
    player_two.position.x = right_building.position.x + right_building.size.width / 2 - player_two.size.width / 2
    player_two.position.y = right_building.position.y + right_building.size.height
  end
end

# System: Handle player input for angle and velocity
def handle_input(args)
  turn = args.state.world.current_turn
  return unless turn && turn.turn
  
  # Skip input handling if both angle and velocity are committed
  return if turn.turn.angle_committed && turn.turn.velocity_committed
  
  # Get inputs from the game args
  inputs = args.inputs
  
  # Handle Enter key for committing values
  if inputs.keyboard.key_down.enter
    if !turn.turn.angle_committed
      turn.turn.angle_committed = true
    elsif !turn.turn.velocity_committed
      turn.turn.velocity_committed = true
      launch_projectile(args, turn.turn)
    end
  # Handle Backspace key for deleting characters
  elsif inputs.keyboard.key_down.backspace
    if turn.turn.angle_committed && !turn.turn.velocity_committed
      turn.turn.velocity = turn.turn.velocity[0...-1] if turn.turn.velocity.length > 0
    elsif !turn.turn.angle_committed
      turn.turn.angle = turn.turn.angle[0...-1] if turn.turn.angle.length > 0
    end
  # Handle number keys for entering values
  elsif (char = inputs.keyboard.key_down.char)
    if (0..9).map(&:to_s).include?(char)
      if turn.turn.angle_committed && !turn.turn.velocity_committed
        turn.turn.velocity += char
      elsif !turn.turn.angle_committed
        turn.turn.angle += char
      end
    end
  end
end

# Helper method to launch a projectile based on turn input
def launch_projectile(args, turn)
  current_player_id = turn.current_player
  player = args.state.world.killables.find { |entity| entity.player && entity.player == current_player_id }
  return unless player
  
  # Parse angle and velocity from turn state
  angle_degrees = turn.angle.to_i
  velocity = turn.velocity.to_i
  
  # Convert angle to radians and calculate velocity components
  angle_radians = angle_degrees * Math::PI / 180.0
  
  # Adjust direction based on player (left or right gorilla)
  direction = current_player_id == 1 ? 1 : -1
  vx = direction * Math.cos(angle_radians).abs * velocity * 0.1
  vy = Math.sin(angle_radians) * velocity * 0.1
  
  # Create banana projectile
  args.state.world.entity do
    component :position, {x: player.position.x + (player.size.width / 2), y: player.position.y + player.size.height}
    component :velocity, {x: vx, y: vy}
    component :size, {width: 20, height: 20}
    component :sprite, {path: 'sprites/banana.png'}
    component :collides, true
    component :rendered, true
    component :rotation, 0
    component :owned_by, current_player_id
  end
  
  # Reset turn state for next player
  turn.angle = ""
  turn.velocity = ""
  turn.angle_committed = false
  turn.velocity_committed = false
  
  # Switch to other player
  turn.current_player = turn.current_player == 1 ? 2 : 1
end

# System: Handle rotation of projectiles
def handle_rotation(args)
  world = args.state.world
  world.projectiles.each do |projectile|
    next unless projectile.rotation
    
    # Rotate banana as it flies
    projectile.rotation += 5
    projectile.rotation %= 360
  end
end

# System: Update physics for projectiles with gravity and wind
def update_physics(args)
  world = args.state.world
  # Get gravity entity
  gravity = world.gravity
  gravity_value = gravity ? gravity.speed : 0.1
  
  # Get wind entity
  wind = world.wind
  wind_value = wind ? wind.speed : 0
  
  # Update all projectiles
  world.projectiles.each do |projectile|
    next unless (pos = projectile.position) && (vel = projectile.velocity)
    
    # Apply gravity
    vel.y -= gravity_value
    
    # Apply wind
    vel.x += wind_value * 0.01
    
    # Update position
    pos.x += vel.x
    pos.y += vel.y
    
    # Check if out of screen bounds
    if pos.x < -50 || pos.x > SCREEN_WIDTH + 50 || pos.y < -50
      # Mark for removal
      projectile.ephemeral = true
    end
  end
end

# System: Handle collisions between projectiles and other entities
def handle_collisions(args)
  world = args.state.world
  world.projectiles.each do |projectile|
    next if projectile.respond_to?(:ephemeral) # Skip if already marked for removal
    
    p_pos = projectile.position
    p_size = projectile.size
    p_owner = projectile.owned_by
    
    # Create a collision box for the projectile
    p_box = {
      x: p_pos.x, 
      y: p_pos.y, 
      w: p_size.width, 
      h: p_size.height
    }
    
    # Check for collisions with buildings
    collision_with_building = false
    world.buildings.each do |building|
      next unless building.position && building.size
      
      # Create a collision box for the building
      b_box = {
        x: building.position.x,
        y: building.position.y,
        w: building.size.width,
        h: building.size.height
      }
      
      # Check for intersection
      if boxes_intersect?(p_box, b_box)
        # Hit a building, create an explosion
        create_explosion(args, p_pos.x, p_pos.y)
        projectile.ephemeral = true
        collision_with_building = true
        break
      end
    end
    
    # Skip player collision check if already hit a building
    next if collision_with_building
    
    # Check for collisions with players
    world.killables.each do |player|
      next unless player.player && player.position && player.size
      next if player.player == p_owner # Skip if projectile belongs to this player
      
      # Create a collision box for the player
      k_box = {
        x: player.position.x,
        y: player.position.y,
        w: player.size.width,
        h: player.size.height
      }
      
      # Check for intersection
      if boxes_intersect?(p_box, k_box)
        # Hit a player, create an explosion
        create_explosion(args, p_pos.x, p_pos.y)
        
        # Increment score of the banana owner
        owner = args.state.world.scorekeepers.find { |entity| entity.player == p_owner }
        owner.score += 1 if owner
        
        # Mark for removal
        projectile.ephemeral = true
        
        # Make player explode
        player.explodes = true
        break
      end
    end
  end
end

# Helper method to check if two boxes intersect
def boxes_intersect?(box1, box2)
  # Check if box1 is to the left of box2, or to the right, or below, or above
  !(box1[:x] > box2[:x] + box2[:w] || 
    box1[:x] + box1[:w] < box2[:x] || 
    box1[:y] > box2[:y] + box2[:h] || 
    box1[:y] + box1[:h] < box2[:y])
end

# Helper method to create an explosion entity
def create_explosion(args, x, y)
  world = args.state.world
  world.entity do
    component :position, {x: x - 25, y: y - 25}
    component :size, {width: 50, height: 50}
    component :sprite, {path: 'sprites/explosion.png'}
    component :rendered, true
    component :ephemeral, true
    component :created_at, args.state.tick_count
    component :ttl, 30  # Time to live in frames
  end
end

# System: Handle explosion animations and effects
def handle_explosions(args)
  world = args.state.world
  world.ephemerals.each do |entity|
    next unless entity.created_at && entity.ttl
    
    # Check if explosion has expired
    if args.state.tick_count > entity.created_at + entity.ttl
      entity.ephemeral = true
    end
  end
end

# System: Check if any player has won the game
def check_win(args)
  world = args.state.world
  # Find players with scores
  player_one = world.scorekeepers.find { |entity| entity.player == 1 }
  player_two = world.scorekeepers.find { |entity| entity.player == 2 }
  
  # Check winning condition (3 points to win)
  if player_one && player_one.score >= 3
    # Player one wins
    world.args.outputs.labels << {
      x: SCREEN_WIDTH / 2,
      y: SCREEN_HEIGHT / 2,
      text: "PLAYER 1 WINS!",
      alignment_enum: 1,
      size_enum: 10,
      **FANCY_WHITE
    }
    
    # Reset game if space is pressed
    if world.args.inputs.keyboard.key_down.space
      generate_stage(world)
    end
  elsif player_two && player_two.score >= 3
    # Player two wins
    world.args.outputs.labels << {
      x: SCREEN_WIDTH / 2,
      y: SCREEN_HEIGHT / 2,
      text: "PLAYER 2 WINS!",
      alignment_enum: 1,
      size_enum: 10,
      **FANCY_WHITE
    }
    
    # Reset game if space is pressed
    if world.args.inputs.keyboard.key_down.space
      generate_stage(world)
    end
  end
end

# System: Render background
def render_background(args)
  world = args.state.world
  bg = world.entities.find { |e| e.background_color }
  if bg && bg.background_color
    args.outputs.background_color = [
      bg.background_color.r,
      bg.background_color.g,
      bg.background_color.b
    ]
  else
    world.args.outputs.background_color = [41, 44, 53]
  end
end

# System: Render buildings and static elements
def render_buildings(args)
  world = args.state.world
  world.buildings.each do |entity|
    next unless entity.position && entity.size && entity.sprite
    
    args.outputs.sprites << {
      x: entity.position.x,
      y: entity.position.y,
      w: entity.size.width,
      h: entity.size.height,
      path: entity.sprite.path,
      r: entity.sprite.r,
      g: entity.sprite.g,
      b: entity.sprite.b
    }
  end
end

# System: Render dynamic sprites
def render_sprites(args)
  world = args.state.world
  world.renderables.each do |entity|
    next unless entity.position && entity.sprite
    
    sprite_hash = {
      x: entity.position.x,
      y: entity.position.y,
      path: entity.sprite.path
    }
    
    # Add size if available
    if entity.size
      sprite_hash[:w] = entity.size.width
      sprite_hash[:h] = entity.size.height
    end
    
    # Add rotation if available
    if entity.respond_to?(:rotation)
      sprite_hash[:angle] = entity.rotation
    end
    
    # Add to sprites collection
    args.outputs.sprites << sprite_hash
  end
end

# System: Render UI elements
def render_ui(args)
  world = args.state.world
  # Render scores
  world.scorekeepers.each do |entity|
    next unless entity.player && entity.score != nil
    
    player_id = entity.player
    score = entity.score
    
    # Position based on player
    x = player_id == 1 ? 50 : (SCREEN_WIDTH - 50)
    alignment = player_id == 1 ? 0 : 2
    
    args.outputs.labels << {
      x: x,
      y: SCREEN_HEIGHT - 50,
      text: "Player #{player_id}: #{score}",
      alignment_enum: alignment,
      size_enum: 4,
      **FANCY_WHITE
    }
  end
  
  # Render turn input UI
  turn = world.current_turn
  if turn && turn.turn
    current_player_id = turn.turn.current_player
    
    # Position input based on player
    x = current_player_id == 1 ? 50 : (SCREEN_WIDTH - 50)
    alignment = current_player_id == 1 ? 0 : 2
    
    if turn.turn.angle_committed && !turn.turn.velocity_committed
      text = "Velocity: #{turn.turn.velocity}_"
    else
      text = "Angle: #{turn.turn.angle}_"
    end
    
    args.outputs.labels << {
      x: x,
      y: 50,
      text: text,
      alignment_enum: alignment,
      **FANCY_WHITE
    }
  end
  
  # Render wind indicator
  wind = world.wind
  if wind
    # Draw wind strength and direction
    text = "Wind: #{wind.speed.round(2)}"
    arrow = wind.speed > 0 ? "→" : "←"
    strength = arrow * [wind.speed.abs.round, 5].min
    
    args.outputs.labels << {
      x: SCREEN_WIDTH / 2,
      y: SCREEN_HEIGHT - 100,
      text: text,
      alignment_enum: 1,
      size_enum: 2,
      **FANCY_WHITE
    }
    
    args.outputs.labels << {
      x: SCREEN_WIDTH / 2,
      y: SCREEN_HEIGHT - 130,
      text: strength,
      alignment_enum: 1,
      size_enum: 4,
      **FANCY_WHITE
    }
  end
  
  # Draw instructions
  args.outputs.labels << {
    x: SCREEN_WIDTH / 2,
    y: SCREEN_HEIGHT - 20,
    text: "Enter angle (0-90), press Enter, then velocity (0-99)",
    alignment_enum: 1,
    **FANCY_WHITE
  }
end

# System: Cleanup ephemeral entities
def cleanup_ephemeral(args)
  world = args.state.world
  world.ephemerals.each do |entity|
    world.entities.delete(entity) if entity.ephemeral
  end
end
