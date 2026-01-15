require 'lib/drecs.rb'

RelPosition = Struct.new(:x, :y)


def test_set_parent_creates_relationships(args, assert)
  world = Drecs::World.new

  parent_id = world.spawn(RelPosition.new(0, 0))
  child_id = world.spawn(RelPosition.new(1, 1))

  result = world.set_parent(child_id, parent_id)

  assert.equal! result, true
  assert.equal! world.parent_of(child_id), parent_id
  assert.equal! world.children_of(parent_id), [child_id]
end


def test_clear_parent_removes_relationships(args, assert)
  world = Drecs::World.new

  parent_id = world.spawn(RelPosition.new(0, 0))
  child_id = world.spawn(RelPosition.new(1, 1))

  world.set_parent(child_id, parent_id)
  result = world.clear_parent(child_id)

  assert.equal! result, true
  assert.equal! world.parent_of(child_id), nil
  assert.equal! world.children_of(parent_id), []
end


def test_destroy_cleans_relationships(args, assert)
  world = Drecs::World.new

  parent_id = world.spawn(RelPosition.new(0, 0))
  child_id = world.spawn(RelPosition.new(1, 1))

  world.set_parent(child_id, parent_id)
  world.destroy(parent_id)

  assert.equal! world.parent_of(child_id), nil
end


def test_destroy_subtree_removes_descendants(args, assert)
  world = Drecs::World.new

  parent_id = world.spawn(RelPosition.new(0, 0))
  child_id = world.spawn(RelPosition.new(1, 1))
  grandchild_id = world.spawn(RelPosition.new(2, 2))

  world.set_parent(child_id, parent_id)
  world.set_parent(grandchild_id, child_id)

  result = world.destroy_subtree(parent_id)

  assert.equal! result, true
  assert.equal! world.entity_exists?(parent_id), false
  assert.equal! world.entity_exists?(child_id), false
  assert.equal! world.entity_exists?(grandchild_id), false
end
