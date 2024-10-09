FANCY_WHITE = {r: 253, g: 252, b: 253}

require_relative 'drakkon/bundle.rb'

def defaults(args)
  return unless args.state.tick_count == 0

  set_world(:game)
end

def tick(args)
  defaults(args)
  process_systems(args)
end
