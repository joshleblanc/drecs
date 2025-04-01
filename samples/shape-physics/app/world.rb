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
    @world.system MovementSystem
    @world.system BoundarySystem
    @world.system PlayerControlSystem
    @world.system CollisionSystem
    @world.system LifetimeSystem
    @world.system RenderSystem
  end
  
  def setup_entities
    # Create a player-controlled circle

    @world.entity PlayerCircle
    
    # Create some bouncing squares at random positions
    10.times do
      @world.entity BouncingSquare, {
        position: {
          x: 100 + rand(1080),
          y: 100 + rand(520)
        },
        velocity: {
          dx: -4 + rand(8),
          dy: -4 + rand(8)
        },
        shape: {
          color: [128 + rand(128), 0, 128 + rand(128)]
        }
      }
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
