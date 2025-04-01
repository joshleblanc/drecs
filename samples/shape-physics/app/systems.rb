# Systems for our shape physics sample
# These demonstrate the new class-based System API

# MovementSystem updates positions based on velocities
class MovementSystem < Drecs::System
  with Position, Velocity
  
  def each(entity)
    entity.position.x += entity.velocity.dx
    entity.position.y += entity.velocity.dy
  end
end

# BoundarySystem keeps entities within the screen boundaries
class BoundarySystem < Drecs::System
  with Position, Velocity, Shape
  
  def each(entity)
    pos = entity.position
    vel = entity.velocity
    half_width = entity.shape.width / 2
    half_height = entity.shape.height / 2
      
    # Check X boundaries
    if pos.x - half_width < 0
      pos.x = half_width
      vel.dx = -vel.dx if entity.collider&.bouncy
    elsif pos.x + half_width > 1280
      pos.x = 1280 - half_width
      vel.dx = -vel.dx if entity.collider&.bouncy
    end
    
    # Check Y boundaries
    if pos.y - half_height < 0
      pos.y = half_height
      vel.dy = -vel.dy if entity.collider&.bouncy
    elsif pos.y + half_height > 720
      pos.y = 720 - half_height
      vel.dy = -vel.dy if entity.collider&.bouncy
    end
  end
end

# PlayerControlSystem handles player input
class PlayerControlSystem < Drecs::System
  with Position, Velocity, Player
  
  def each(entity)
    # Skip if no keyboard input is available
    next unless world.args.inputs.keyboard
      
    vel = entity.velocity
    speed = entity.player.speed
      
    # Reset velocity first
    vel.dx = 0
    vel.dy = 0
      
    # Apply movement based on keypresses
    vel.dx -= speed if world.args.inputs.keyboard.key_held.a || world.args.inputs.keyboard.key_held.left
    vel.dx += speed if world.args.inputs.keyboard.key_held.d || world.args.inputs.keyboard.key_held.right
    vel.dy -= speed if world.args.inputs.keyboard.key_held.w || world.args.inputs.keyboard.key_held.up
    vel.dy += speed if world.args.inputs.keyboard.key_held.s || world.args.inputs.keyboard.key_held.down
  end
end

# CollisionSystem detects and responds to collisions between entities
class CollisionSystem < Drecs::System
  with Position, Collider
  
  def each(entity)
    @particle_cooldown = 0
    
    # Get all other entities with Position and Collider
    world.with(Position, Collider).each do |other|
      # Skip checking against self
      next if entity == other
      
      # Calculate distance between entities
      dx = entity.position.x - other.position.x
      dy = entity.position.y - other.position.y
      distance = Math.sqrt(dx * dx + dy * dy)
        
      # Check if colliding
      min_distance = entity.collider.radius + other.collider.radius
      if distance < min_distance
        # Handle collision
        if entity.velocity && other.velocity
          # Only handle collision once (from one entity's perspective)
          if entity._id < other._id
            handle_collision(entity, other, dx, dy, distance)
          end
        end
      end
    end
  end
  
  private
  
  def handle_collision(entity1, entity2, dx, dy, distance)
    # Normalize collision vector
    nx = dx / distance
    ny = dy / distance
    
    # Calculate relative velocity
    vx = entity1.velocity.dx - entity2.velocity.dx
    vy = entity1.velocity.dy - entity2.velocity.dy
    
    # Calculate velocity along collision normal
    vnorm = vx * nx + vy * ny
    
    # Don't resolve if objects are moving away from each other
    return if vnorm > 0
    
    # Calculate bounce response (simplified)
    impulse = -2.0 * vnorm / 2.0 # Assume equal mass
    
    # Apply impulse
    entity1.velocity.dx += impulse * nx
    entity1.velocity.dy += impulse * ny
    entity2.velocity.dx -= impulse * nx
    entity2.velocity.dy -= impulse * ny
    
    # Create particles if cooldown allows
    if @particle_cooldown <= 0
      # Create particles at collision point
      midpoint_x = (entity1.position.x + entity2.position.x) / 2
      midpoint_y = (entity1.position.y + entity2.position.y) / 2
      
      # Create 5 particles
      5.times do
        world.entity(CollisionParticle.new(midpoint_x, midpoint_y))
      end
      
      # Set cooldown to prevent too many particles
      @particle_cooldown = 5
    end
    
    # Decrease cooldown
    @particle_cooldown -= 1
  end
end

# RenderSystem handles drawing entities to the screen
class RenderSystem < Drecs::System
  with Position, Shape
  
  def each(entity)
    pos = entity.position
    shape = entity.shape
      
    primitive = {
      x: pos.x - shape.width / 2, 
      y: pos.y - shape.height / 2,
      w: shape.width,
      h: shape.height,
      primitive_marker: :solid,
      r: shape.color[0],
      g: shape.color[1],
      b: shape.color[2]
    }
      
    # Add to outputs
    world.args.outputs.primitives << primitive if primitive
  end
end

# LifetimeSystem manages entities with limited lifetimes
class LifetimeSystem < Drecs::System
  with Lifetime
  
  def each(entity)
    # Calculate how long the entity has existed
    current_time = Kernel.tick_count
    age = current_time - entity.lifetime.created_at
      
    # Mark for removal if exceeded duration
    if age >= entity.lifetime.duration
      world.entities.delete(entity)
    end
  end
end
