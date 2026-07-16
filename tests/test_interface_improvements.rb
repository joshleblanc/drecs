require 'lib/drecs.rb'

# Test-only component classes
PositionTagTest = Struct.new(:x, :y)
FindEntityPos   = Struct.new(:x, :y)

# Components used by migration tests
PositionMigration = Struct.new(:x, :y)
VelocityMigration = Struct.new(:dx, :dy)
HealthMigration   = Struct.new(:hp)

PositionMig2 = Struct.new(:x, :y)
VelocityMig2 = Struct.new(:dx, :dy)

# ---------------------------------------------------------------------------
# Drecs.tag
# ---------------------------------------------------------------------------

def test_drecs_tag_exposes_tag_name_on_class_and_instance(args, assert)
  player_klass = Drecs.tag(:player)
  assert.equal! player_klass.tag_name, :player
  assert.equal! player_klass.new.tag_name, :player
end

def test_drecs_tag_is_not_a_struct_and_does_not_collide(args, assert)
  # Tags must not define global Struct constants — two tags with the same
  # name are distinct classes (distinct archetype signatures) and creating
  # the second must not raise or emit a redefinition warning.
  k1 = Drecs.tag(:bullet)
  k2 = Drecs.tag(:bullet)
  assert.equal! k1.ancestors.include?(Struct), false
  assert.equal! k1 == k2, false
  assert.equal! k1.tag_name, k2.tag_name
end

def test_drecs_tag_carries_zero_fields(args, assert)
  tag_klass = Drecs.tag(:marker)
  assert.equal! tag_klass.new.members, []
  assert.equal! tag_klass.new.values, []
end

def test_drecs_tag_anonymous_when_no_name(args, assert)
  anon = Drecs.tag
  assert.equal! anon.name.nil?, true
  assert.equal! anon.tag_name.nil?, true
end

def test_drecs_tag_works_as_component(args, assert)
  w = Drecs::World.new
  tag_klass = Drecs.tag(:enemy)
  id = w.spawn(PositionTagTest.new(1, 2), tag_klass.new)
  assert.equal! w.has_component?(id, tag_klass), true
  found = []
  w.each_entity(PositionTagTest, with: tag_klass) { |eid, _pos| found << eid }
  assert.equal! found, [id]
end

# ---------------------------------------------------------------------------
# World.new validation kwarg:
# ---------------------------------------------------------------------------

def test_world_new_validation_defaults_to_off(args, assert)
  w = Drecs::World.new
  assert.equal! w.instance_variable_get(:@validate_components), false
end

def test_world_new_validation_kwarg_turns_it_on(args, assert)
  w = Drecs::World.new(validate_components: true)
  assert.equal! w.instance_variable_get(:@validate_components), true
end

def test_world_new_invalid_kwarg_raises(args, assert)
  raised = false
  begin
    Drecs::World.new(never_a_valid_kwarg: 1)
  rescue ArgumentError
    raised = true
  end
  assert.equal! raised, true
end

# ---------------------------------------------------------------------------
# commands / commands!
# ---------------------------------------------------------------------------

def test_commands_defers_until_flush(args, assert)
  w = Drecs::World.new
  before = w.entity_count
  w.commands { |cmd| cmd.spawn(PositionTagTest.new(1, 2)) }
  assert.equal! w.entity_count, before
  w.flush_defer!
  assert.equal! w.entity_count, before + 1
end

def test_commands_bang_applies_immediately(args, assert)
  w = Drecs::World.new
  before = w.entity_count
  w.commands! { |cmd| cmd.spawn(PositionTagTest.new(1, 2)) }
  assert.equal! w.entity_count, before + 1
end

# ---------------------------------------------------------------------------
# Event helpers
# ---------------------------------------------------------------------------

def test_event_helpers_count_and_check(args, assert)
  w = Drecs::World.new
  assert.equal! w.event?(:hit), false
  assert.equal! w.event_count(:hit), 0
  assert.equal! w.events(:hit), []

  w.send_event(:hit, { a: 1 })
  w.send_event(:hit, { a: 2 })

  assert.equal! w.event?(:hit), true
  assert.equal! w.event_count(:hit), 2
  assert.equal! w.events(:hit).length, 2
end

# ---------------------------------------------------------------------------
# find_entity
# ---------------------------------------------------------------------------

def test_find_entity_no_predicate_returns_first_match(args, assert)
  w = Drecs::World.new
  id = w.spawn(FindEntityPos.new(1, 2))
  result = w.find_entity(FindEntityPos)
  assert.equal! result, id
end

def test_find_entity_predicate_filters(args, assert)
  w = Drecs::World.new
  id1 = w.spawn(FindEntityPos.new(1, 2))
  id2 = w.spawn(FindEntityPos.new(3, 4))
  result = w.find_entity(FindEntityPos) { |_id, pos| pos.x == 3 }
  assert.equal! result, id2
end

def test_find_entity_no_match_returns_nil(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  result = w.find_entity(FindEntityPos) { |_id, pos| pos.x > 1000 }
  assert.equal! result, nil
end

# ---------------------------------------------------------------------------
# fetch_resource / has_resource?
# ---------------------------------------------------------------------------

def test_fetch_resource_returns_value(args, assert)
  w = Drecs::World.new
  w.insert_resource(:score, 100)
  assert.equal! w.fetch_resource(:score), 100
end

def test_fetch_resource_missing_with_block_returns_default(args, assert)
  w = Drecs::World.new
  assert.equal! w.fetch_resource(:nope) { 42 }, 42
end

def test_fetch_resource_missing_without_block_raises(args, assert)
  w = Drecs::World.new
  raised = false
  begin
    w.fetch_resource(:nope)
  rescue KeyError
    raised = true
  end
  assert.equal! raised, true
end

def test_has_resource_predicate(args, assert)
  w = Drecs::World.new
  w.insert_resource(:score, 1)
  assert.equal! w.has_resource?(:score), true
  assert.equal! w.has_resource?(:nope), false
end

# ---------------------------------------------------------------------------
# cached_query / component_classes
# ---------------------------------------------------------------------------

def test_cached_query_returns_query(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  q = w.cached_query(FindEntityPos)
  assert.equal! q.is_a?(Drecs::Query), true
  assert.equal! q.matching_archetypes.length > 0, true
end

def test_query_for_alias_still_works(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  q = w.query_for(FindEntityPos)
  assert.equal! q.is_a?(Drecs::Query), true
end

def test_component_classes_lists_all_components(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  classes = w.component_classes
  assert.equal! classes.include?(FindEntityPos), true
end

# ---------------------------------------------------------------------------
# validate!
# ---------------------------------------------------------------------------

def test_validate_passes_on_clean_world(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  w.validate!
  assert.equal! true, true
end

# ---------------------------------------------------------------------------
# snapshot / restore
# ---------------------------------------------------------------------------

def test_snapshot_captures_entity_count(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  w.spawn(FindEntityPos.new(3, 4))
  snap = w.snapshot
  assert.equal! snap[:entities].length, 2
end

def test_round_trip_snapshot_restore(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  w.insert_resource(:score, 50)

  snap = w.snapshot
  w2 = Drecs::World.new
  w2.restore(snap)

  assert.equal! w2.entity_count, w.entity_count
  assert.equal! w2.fetch_resource(:score), 50
end

# ---------------------------------------------------------------------------
# dump
# ---------------------------------------------------------------------------

def test_dump_returns_string_with_entity_count(args, assert)
  w = Drecs::World.new
  w.spawn(FindEntityPos.new(1, 2))
  out = w.dump
  assert.equal! out.is_a?(String), true
  assert.equal! out.include?("1 entities"), true
end

# ---------------------------------------------------------------------------
# set_components migration always-bumps (Phase 3.1)
# ---------------------------------------------------------------------------

def test_set_components_migration_bumps_carried_components(args, assert)
  w = Drecs::World.new
  w.advance_change_tick!
  e = w.spawn(PositionMigration.new(0, 0), VelocityMigration.new(1, 1))
  w.advance_change_tick!

  w.set_components(e, HealthMigration.new(10))
  pos_bumped    = w.ids(PositionMigration, changed: [PositionMigration])
  vel_bumped    = w.ids(VelocityMigration, changed: [VelocityMigration])
  health_bumped = w.ids(HealthMigration,    changed: [HealthMigration])

  assert.equal! pos_bumped, [e]
  assert.equal! vel_bumped, [e]
  assert.equal! health_bumped, [e]
end

def test_set_components_no_migration_only_bumps_touched(args, assert)
  w = Drecs::World.new
  w.advance_change_tick!
  e = w.spawn(PositionMig2.new(0, 0), VelocityMig2.new(1, 1))
  w.advance_change_tick!

  # Same archetype — no migration
  w.set_components(e, VelocityMig2.new(2, 3))
  pos_changed = w.ids(PositionMig2, changed: [PositionMig2])
  assert.equal! pos_changed, []
end
