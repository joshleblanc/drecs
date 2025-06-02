require 'lib/drecs'

# Game constants
FANCY_WHITE = { r: 253, g: 252, b: 253 }.freeze
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720

# Game state
def boot(args)
  world = Drecs.world
  
  # Define queries
  world.query do
    with(:position, :player)
    as :players
  end
  
  world.query do
    with(:position, :building)
    as :buildings
  end
  
  world.query do
    with(:position, :projectile)
    as :projectiles
  end
  
  # Create initial game state
  create_players(world)
  create_buildings(world)
  
  # Add turn state
  world.entity do
    name :turn_state
    component :current_player, 1
    component :angle, ""
    component :velocity, ""
    component :angle_committed, false
    component :velocity_committed, false
  end
  
  # Add wind
  world.entity do
    name :wind
    as :wind
    component :speed, 0.0
  end
  
  world
end

def create_players(world)
  # Player 1
  world.entity do
    component :position, {x: 100, y: 200}
    component :player, {id: 1}
    component :sprite, {path: 'sprites/gorilla1.png', w: 50, h: 50}
    component :score, 0
  end
  
  # Player 2
  world.entity do
    component :position, {x: 1180, y: 200}
    component :player, {id: 2}
    component :sprite, {path: 'sprites/gorilla2.png', w: 50, h: 50}
    component :score, 0
  end
end

def create_buildings(world)
  # Create ground
  world.entity do
    component :position, {x: 0, y: 0, w: SCREEN_WIDTH, h: 100}
    component :building, true
    component :sprite, {path: :pixel, r: 100, g: 100, b: 100}
  end
  
  # Add some buildings
  building_width = 150
  gap = 50
  ground_y = 100
  
  # Left buildings
  (0..2).each do |i|
    height = 100 + rand(200)
    world.entity do
      component :position, {x: i * (building_width + gap), y: ground_y, w: building_width, h: height}
      component :building, true
      component :sprite, {path: :pixel, r: 80, g: 80, b: 90}
    end
  end
  
  # Right buildings
  (7..9).each do |i|
    height = 100 + rand(200)
    world.entity do
      component :position, {x: i * (building_width + gap), y: ground_y, w: building_width, h: height}
      component :building, true
      component :sprite, {path: :pixel, r: 80, g: 80, b: 90}
    end
  end
end

def tick(args)
  world = args.state.world ||= boot(args)
  
  # Update game state
  update_input(world, args.inputs)
  update_physics(world)
  
  # Render
  render(world, args.outputs)
end

def update_input(world, inputs)
  turn = world.entities.find { |e| e.name == :turn_state }
  return unless turn
  
  if inputs.keyboard.key_down.enter
    if turn.angle_committed
      turn.velocity_committed = true
      launch_projectile(world, turn)
    else
      turn.angle_committed = true
    end
  elsif inputs.keyboard.key_down.backspace
    if turn.angle_committed
      turn.velocity = turn.velocity[0...-1]
    else
      turn.angle = turn.angle[0...-1]
    end
  elsif (char = inputs.keyboard.key_down.char)
    if char =~ /\d/
      if turn.angle_committed
        turn.velocity += char
      else
        turn.angle += char
      end
    end
  end
end

def launch_projectile(world, turn)
  player = world.players.find { |p| p.player.id == turn.current_player }
  return unless player
  
  angle = turn.angle.to_i
  velocity = turn.velocity.to_i
  
  # Convert angle and velocity to x,y components
  rad = angle * Math::PI / 180.0
  vx = Math.cos(rad) * velocity * 0.1
  vy = Math.sin(rad) * velocity * 0.1
  
  world.entity do
    component :position, {x: player.position.x, y: player.position.y}
    component :velocity, {x: vx, y: vy}
    component :projectile, true
    component :sprite, {path: 'sprites/banana.png', w: 20, h: 20}
  end
  
  # Reset turn state
  turn.angle = ""
  turn.velocity = ""
  turn.angle_committed = false
  turn.velocity_committed = false
  turn.current_player = turn.current_player == 1 ? 2 : 1
end

def update_physics(world)
  # Update projectiles
  world.projectiles.each do |projectile|
    next unless (pos = projectile.position) && (vel = projectile.velocity)
    
    # Apply gravity
    vel.y -= 0.1
    
    # Update position
    pos.x += vel.x
    pos.y += vel.y
    
    # Check for collisions with buildings
    world.buildings.each do |building|
      next unless (bpos = building.position) && (bsize = building.size)
      
      if pos.x >= bpos.x && pos.x <= bpos.x + bsize.w &&
         pos.y >= bpos.y && pos.y <= bpos.y + bsize.h
        # Hit a building
        world.entities.delete(projectile)
        break
      end
    end
    
    # Check for collisions with players
    world.players.each do |player|
      next if player.player.id == world.entities.find { |e| e.name == :turn_state }.current_player
      next unless (ppos = player.position) && (psize = player.size)
      
      if pos.x >= ppos.x && pos.x <= ppos.x + psize.w &&
         pos.y >= ppos.y && pos.y <= ppos.y + psize.h
        # Hit a player
        player.score += 1
        world.entities.delete(projectile)
        break
      end
    end
    
    # Check if out of bounds
    if pos.y < 0 || pos.x < 0 || pos.x > SCREEN_WIDTH
      world.entities.delete(projectile)
    end
  end
  
  # Update wind
  world.wind.speed += (rand - 0.5) * 0.1
  world.wind.speed = world.wind.speed.clamp(-2.0, 2.0)
end

def render(world, outputs)
  # Clear screen
  outputs.background_color = [41, 44, 53]
  
  # Render buildings
  world.buildings.each do |building|
    next unless (pos = building.position) && (sprite = building.sprite)
    outputs.sprites << {
      x: pos.x, y: pos.y, w: pos.w || 100, h: pos.h || 100,
      path: sprite.path, r: sprite.r, g: sprite.g, b: sprite.b
    }
  end
  
  # Render players
  world.players.each do |player|
    next unless (pos = player.position) && (sprite = player.sprite)
    outputs.sprites << {
      x: pos.x, y: pos.y, w: sprite.w, h: sprite.h,
      path: sprite.path
    }
    
    # Render score
    outputs.labels << {
      x: player.player.id == 1 ? 50 : 1230,
      y: 700,
      text: "P#{player.player.id}: #{player.score}",
      **FANCY_WHITE,
      size_enum: 4
    }
  end
  
  # Render projectiles
  world.projectiles.each do |projectile|
    next unless (pos = projectile.position) && (sprite = projectile.sprite)
    outputs.sprites << {
      x: pos.x, y: pos.y, w: sprite.w, h: sprite.h,
      path: sprite.path
    }
  end
  
  # Render UI
  turn = world.entities.find { |e| e.name == :turn_state }
  if turn
    player = world.players.find { |p| p.player.id == turn.current_player }
    if player
      x = player.player.id == 1 ? 50 : 1000
      
      if turn.angle_committed
        outputs.labels << {
          x: x, y: 100, text: "Velocity: #{turn.velocity}_", **FANCY_WHITE
        }
      else
        outputs.labels << {
          x: x, y: 100, text: "Angle: #{turn.angle}_", **FANCY_WHITE
        }
      end
    end
  end
  
  # Render wind
  if (wind = world.entities.find { |e| e.name == :wind })
    outputs.labels << {
      x: SCREEN_WIDTH / 2, y: 700, text: "Wind: #{'%.1f' % wind.speed}",
      **FANCY_WHITE, alignment_enum: 1, size_enum: 4
    }
  end
end
