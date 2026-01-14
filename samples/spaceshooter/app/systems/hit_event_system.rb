class HitEventSystem
  def call(world, args)
    hit_events = world.each_event(HitEvent)
    return nil if hit_events.nil?

    ids = {}
    hit_events.each do |evt|
      ids[evt.bullet_id] = true
      ids[evt.enemy_id] = true
    end

    unless ids.empty?
      world.destroy(*ids.keys)
    end

    world.clear_events!(HitEvent)
    nil
  end
end
