require "lib/drecs"

include Drecs::Main

FANCY_WHITE = { r: 253, g: 252, b: 253 }

require_relative "entities"
require_relative "components"
require_relative "systems"

def defaults(args)
  return unless args.state.tick_count == 0
end

def tick(args)
  defaults(args)
  process_systems(args)
end
