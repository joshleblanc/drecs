class LifetimeSystem
  def call(world, args)
    to_destroy = []

    world.each_entity(Lifetime) do |entity_id, lifetime|
      lifetime.ticks -= 1

      if lifetime.ticks <= 0
        to_destroy << entity_id
      end
    end

    world.commands { |cmd| cmd.destroy(*to_destroy) } unless to_destroy.empty?
  end
end
