require_relative "lib/drecs"
require_relative "game"

def tick(args)
  args.state.game ||= Game.new
  args.state.game.args = args
  args.state.game.tick
end
