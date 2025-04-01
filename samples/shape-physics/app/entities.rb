# Entities for our shape physics sample
# These demonstrate the new class-based Entity API

# PlayerCircle is a player-controlled circle that can collide with other objects

class PlayerCircle < Drecs::Entity
  component Position, x: 400, y: 300
  component Velocity, dx: 0, dy: 0
  component Shape, type: :circle, width: 30, height: 30, color: [0, 255, 0]
  component Collider, radius: 15, bouncy: true
  component Player, speed: 5
end

# BouncingSquare is an AI-controlled square that bounces around
class BouncingSquare < Drecs::Entity
  component Position, x: 0, y: 0
  component Velocity, dx: 3, dy: 2
  component Shape, type: :square, width: 40, height: 40, color: [255, 0, 0]
  component Collider, radius: 20, bouncy: true
end

# CollisionParticle is a small, temporary visual effect
class CollisionParticle < Drecs::Entity
  component Position, x: 0, y: 0
  component Velocity, dx: 0, dy: 0
  component Shape, type: :circle, width: 10, height: 10, color: [255, 255, 0]
  component Lifetime, duration: 30, created_at: 0
  
  # Override default values with custom initialization
  def initialize(x, y, color = nil)
    super()
    
    # Set position to the provided coordinates
    position.x = x
    position.y = y
    
    # Set random velocity in a circular pattern
    angle = rand * Math::PI * 2
    speed = 1 + rand * 3
    velocity.dx = Math.cos(angle) * speed
    velocity.dy = Math.sin(angle) * speed
    
    # Set custom color if provided
    shape.color = color if color
    
    # Set the creation time to now
    lifetime.created_at = Kernel.tick_count
  end
end
