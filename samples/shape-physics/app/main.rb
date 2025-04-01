# Main entry point for our shape physics sample
# Demonstrates the new class-based API for the DRECS library

# Require all the necessary files
require_relative 'components.rb'
require_relative 'entities.rb'
require_relative 'systems.rb'
require_relative 'world.rb'

# Initialize the game world
$game_world = GameWorld.new

def tick(args)
  # Delegate to our game world
  $game_world.tick(args)
end
