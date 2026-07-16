require 'lib/drecs.rb'

# Regression tests for the fixes from the 2026-07 code review:
#   - restore: component copying (formerly used a non-existent map_values),
#     mixed struct/hash entities, Parent/Children id remapping
#   - snapshot: one-level deep copies of nested Array/Hash field values
#   - normalize_signature: anonymous component classes must not crash
#   - validate!: component_changed_at desync detection
#   - each_chunk: deferred commands flush when iteration ends

RegPosition  = Struct.new(:x, :y)
RegInventory = Struct.new(:items)

# ---------------------------------------------------------------------------
# restore
# ---------------------------------------------------------------------------

def test_restore_round_trips_struct_components(args, assert)
  w = Drecs::World.new
  w.spawn(RegPosition.new(1, 2))
  w.spawn(RegPosition.new(3, 4))

  w2 = Drecs::World.new
  w2.restore(w.snapshot)

  assert.equal! w2.entity_count, 2
  xs = []
  w2.each_entity(RegPosition) { |_id, pos| xs << pos.x }
  assert.equal! xs.sort, [1, 3]
end

def test_restore_round_trips_hash_components(args, assert)
  w = Drecs::World.new
  w.spawn({ health: { hp: 10 }, mana: { mp: 5 } })

  w2 = Drecs::World.new
  w2.restore(w.snapshot)

  assert.equal! w2.entity_count, 1
  id = w2.all_entity_ids.first
  assert.equal! w2.get_component(id, :health)[:hp], 10
  assert.equal! w2.get_component(id, :mana)[:mp], 5
end

def test_restore_round_trips_mixed_struct_and_hash_components(args, assert)
  w = Drecs::World.new
  id = w.spawn(RegPosition.new(7, 8))
  w.add_component(id, :score, { points: 42 })

  w2 = Drecs::World.new
  w2.restore(w.snapshot)

  new_id = w2.all_entity_ids.first
  assert.equal! w2.get_component(new_id, RegPosition).x, 7
  assert.equal! w2.get_component(new_id, :score)[:points], 42
end

def test_restore_decouples_restored_world_from_snapshot(args, assert)
  w = Drecs::World.new
  w.spawn(RegPosition.new(1, 2))
  snap = w.snapshot

  w2 = Drecs::World.new
  w2.restore(snap)
  w2.each_entity(RegPosition) { |_id, pos| pos.x = 99 }

  # Restoring the same snapshot again must yield the original value.
  w3 = Drecs::World.new
  w3.restore(snap)
  xs = []
  w3.each_entity(RegPosition) { |_id, pos| xs << pos.x }
  assert.equal! xs, [1]
end

def test_restore_remaps_parent_child_relationships(args, assert)
  w = Drecs::World.new
  # Spawn filler entities first so re-idding produces different ids.
  filler = w.spawn(RegPosition.new(0, 0))
  parent = w.spawn(RegPosition.new(1, 1))
  child  = w.spawn(RegPosition.new(2, 2))
  w.set_parent(child, parent)
  w.destroy(filler)

  snap = w.snapshot
  w2 = Drecs::World.new
  w2.restore(snap)

  new_parent = nil
  new_child = nil
  w2.each_entity(RegPosition) do |id, pos|
    new_parent = id if pos.x == 1
    new_child  = id if pos.x == 2
  end

  assert.equal! w2.parent_of(new_child), new_parent
  assert.equal! w2.children_of(new_parent), [new_child]
end

def test_restore_yields_id_map(args, assert)
  w = Drecs::World.new
  old_id = w.spawn(RegPosition.new(5, 5))

  w2 = Drecs::World.new
  captured = nil
  w2.restore(w.snapshot) { |id_map| captured = id_map }

  assert.equal! captured.nil?, false
  assert.equal! captured.key?(old_id), true
  assert.equal! w2.entity_exists?(captured[old_id]), true
end

# ---------------------------------------------------------------------------
# snapshot nested-collection copying
# ---------------------------------------------------------------------------

def test_snapshot_copies_nested_array_fields(args, assert)
  w = Drecs::World.new
  id = w.spawn(RegInventory.new([:sword]))

  snap = w.snapshot
  w.get_component(id, RegInventory).items << :shield

  snap_items = snap[:entities].first[1][RegInventory].items
  assert.equal! snap_items, [:sword]
end

# ---------------------------------------------------------------------------
# anonymous component classes
# ---------------------------------------------------------------------------

def test_anonymous_component_classes_do_not_crash_signatures(args, assert)
  w = Drecs::World.new
  anon_a = Drecs.component(:v)
  anon_b = Drecs.component(:v)

  id = w.spawn(anon_a.new(1), anon_b.new(2), RegPosition.new(0, 0))
  assert.equal! w.get_component(id, anon_a).v, 1
  assert.equal! w.get_component(id, anon_b).v, 2

  found = []
  w.each_entity(anon_a, anon_b) { |eid, a, b| found << [eid, a.v, b.v] }
  assert.equal! found, [[id, 1, 2]]
end

# ---------------------------------------------------------------------------
# validate! changed_at coverage
# ---------------------------------------------------------------------------

def test_validate_detects_changed_at_desync(args, assert)
  w = Drecs::World.new
  w.spawn(RegPosition.new(1, 2))
  assert.equal! w.validate!, true

  archetype = w.archetypes.values.first
  archetype.component_changed_at[RegPosition].pop

  raised = false
  begin
    w.validate!
  rescue Drecs::IntegrityError
    raised = true
  end
  assert.equal! raised, true
end

# ---------------------------------------------------------------------------
# each_chunk iteration tracking
# ---------------------------------------------------------------------------

def test_each_chunk_flushes_deferred_commands_after_iteration(args, assert)
  w = Drecs::World.new
  doomed = w.spawn(RegPosition.new(1, 1))

  w.each_chunk(RegPosition) do |ids, _positions|
    assert.equal! w.in_iteration?, true
    w.defer { |world| world.destroy(doomed) }
    # Deferred work must NOT run mid-iteration.
    assert.equal! w.entity_exists?(doomed), true
  end

  assert.equal! w.in_iteration?, false
  assert.equal! w.entity_exists?(doomed), false
end
