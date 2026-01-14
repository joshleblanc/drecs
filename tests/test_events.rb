require 'lib/drecs.rb'

DamageEvent = Struct.new(:target_id, :amount)

def test_events_buffer_and_clear_all(args, assert)
  world = Drecs::World.new

  world.send_event(DamageEvent.new(1, 5))
  world.send_event(DamageEvent.new(2, 3))

  events = []
  world.each_event(DamageEvent) { |evt| events << evt }

  assert.equal! events.map(&:target_id), [1, 2]
  assert.equal! events.map(&:amount), [5, 3]

  world.clear_events!
  assert.equal! world.each_event(DamageEvent).to_a, []
end

def test_events_clear_by_type(args, assert)
  world = Drecs::World.new

  world.send_event(DamageEvent.new(1, 5))
  world.send_event(:log, { msg: "hi" })

  world.clear_events!(DamageEvent)

  assert.equal! world.each_event(DamageEvent).to_a, []
  assert.equal! world.each_event(:log).to_a.length, 1
end

def test_events_auto_clear_on_advance_change_tick(args, assert)
  world = Drecs::World.new

  world.send_event(DamageEvent.new(1, 5))
  assert.equal! world.each_event(DamageEvent).to_a.length, 1

  world.advance_change_tick!
  assert.equal! world.each_event(DamageEvent).to_a, []
end
