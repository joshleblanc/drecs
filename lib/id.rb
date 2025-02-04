module Drecs 
  class Id 
    include FFI::Flecs

    attr_reader :world, :value

    def initialize(world: nil, value: nil, expr: nil, first: nil, second: nil)
      @world = world
      @value = value

      if expr
        @value = ecs_id_from_str(world, expr)
      end

      if first && second
        @value = ecs_id_pair(world, first, second)
      end
    end
  end
end
