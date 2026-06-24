# LifetimeSystem - destroys entities whose lifetime has expired
# This system showcases: each_entity with component modification,
#                       and safe destruction during iteration via commands
class LifetimeSystem
  def call(world, args)
    expired = []

    world.each_entity(Lifetime) do |entity_id, lifetime|
      lifetime.tick!
      world.set_component(entity_id, lifetime)

      if lifetime.expired?
        expired << entity_id
      end
    end

    # Use commands to safely destroy during iteration
    unless expired.empty?
      world.commands { |cmd| cmd.destroy(*expired) }
    end
  end
end