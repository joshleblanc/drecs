# Setup for our game world
# This demonstrates the class-based approach for game world setup

# GameWorld class creates and configures our game world
class GameWorld
  attr_reader :world
  
  def initialize
    @world = Drecs.world do
      # Set a name for debugging
      name "Shape Physics World"
      
      # Enable debugging if needed
      # debug true
    end
    
    setup_systems
    setup_entities
  end
  
  def setup_systems
    # Add all of our systems in execution order
    @world.add_system(MovementSystem.new)
    @world.add_system(BoundarySystem.new)
    @world.add_system(PlayerControlSystem.new)
    @world.add_system(CollisionSystem.new)
    @world.add_system(LifetimeSystem.new)
    @world.add_system(RenderSystem.new) # Render should be last
  end
  
  def setup_entities
    # Create a player-controlled circle
    @world.entity(PlayerCircle)
    
    # Create some bouncing squares at random positions
    10.times do
      square = BouncingSquare.new
      
      # Randomize starting position
      square.position.x = 100 + rand(1080)
      square.position.y = 100 + rand(520)
      
      # Randomize velocity
      square.velocity.dx = -4 + rand(8)
      square.velocity.dy = -4 + rand(8)
      
      # Randomize color (shades of red and blue)
      r = 128 + rand(128)
      b = 128 + rand(128)
      square.shape.color = [r, 0, b]
      
      @world.entity(square)
    end
  end
  
  def tick(args)
    # Update the world with current arguments
    @world.tick(args)
    
    # Display instructions
    args.outputs.labels << [10, 710, "Use WASD or Arrow Keys to move the green circle", 0, 0]
    args.outputs.labels << [10, 30, "FPS: #{args.gtk.current_framerate.round}", 0, 0]
  end
end
