# HitEvent - event fired when a projectile hits something
class HitEvent < Struct.new(:projectile_id, :target_id, :damage)
  def initialize(projectile_id = nil, target_id = nil, damage = 0)
    super(projectile_id, target_id, damage)
  end
end

# SpawnEvent - event fired when an enemy spawns
class SpawnEvent < Struct.new(:entity_id, :enemy_type)
  def initialize(entity_id = nil, enemy_type = :basic)
    super(entity_id, enemy_type)
  end
end

# DamageEvent - event for damage dealt to entities
class DamageEvent < Struct.new(:target_id, :amount, :source)
  def initialize(target_id = nil, amount = 0, source = :unknown)
    super(target_id, amount, source)
  end
end

# DeathEvent - event fired when an entity dies
class DeathEvent < Struct.new(:entity_id, :killer_id)
  def initialize(entity_id = nil, killer_id = nil)
    super(entity_id, killer_id)
  end
end

# LootCollectedEvent - event for when loot is picked up
class LootCollectedEvent < Struct.new(:loot_id, :collector_id, :value)
  def initialize(loot_id = nil, collector_id = nil, value = 0)
    super(loot_id, collector_id, value)
  end
end

# TurnEvent - event for turn transitions
class TurnEvent < Struct.new(:current_turn)
  def initialize(current_turn = :player)
    super(current_turn)
  end
end

# ItemPickupEvent - event for when an item is picked up
class ItemPickupEvent < Struct.new(:item_id, :item_type, :value)
  def initialize(item_id = nil, item_type = nil, value = 0)
    super(item_id, item_type, value)
  end
end

# MeleeAttackEvent - event fired when player performs a melee attack
# Contains attacker_id, target_x, target_y (tile coords), and damage
class MeleeAttackEvent < Struct.new(:attacker_id, :target_x, :target_y, :damage)
  def initialize(attacker_id = nil, target_x = 0, target_y = 0, damage = 99)
    super(attacker_id, target_x, target_y, damage)
  end
end

# AttackEvent - event for melee attacks (alternative naming)
class AttackEvent < Struct.new(:attacker_id, :target_id, :damage)
  def initialize(attacker_id = nil, target_id = nil, damage = 0)
    super(attacker_id, target_id, damage)
  end
end