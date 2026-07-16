# HitEvent - event fired when a projectile hits something
class HitEvent
  include Drecs::Component
  component :projectile_id, :target_id, :damage

  def initialize(projectile_id = nil, target_id = nil, damage = 0)
    @projectile_id = projectile_id
    @target_id = target_id
    @damage = damage
  end
end

# SpawnEvent - event fired when an enemy spawns
class SpawnEvent
  include Drecs::Component
  component :entity_id, :enemy_type

  def initialize(entity_id = nil, enemy_type = :basic)
    @entity_id = entity_id
    @enemy_type = enemy_type
  end
end

# DamageEvent - event for damage dealt to entities
class DamageEvent
  include Drecs::Component
  component :target_id, :amount, :source

  def initialize(target_id = nil, amount = 0, source = :unknown)
    @target_id = target_id
    @amount = amount
    @source = source
  end
end

# DeathEvent - event fired when an entity dies
class DeathEvent
  include Drecs::Component
  component :entity_id, :killer_id

  def initialize(entity_id = nil, killer_id = nil)
    @entity_id = entity_id
    @killer_id = killer_id
  end
end

# LootCollectedEvent - event for when loot is picked up
class LootCollectedEvent
  include Drecs::Component
  component :loot_id, :collector_id, :value

  def initialize(loot_id = nil, collector_id = nil, value = 0)
    @loot_id = loot_id
    @collector_id = collector_id
    @value = value
  end
end

# TurnEvent - event for turn transitions
class TurnEvent
  include Drecs::Component
  component :current_turn

  def initialize(current_turn = :player)
    @current_turn = current_turn
  end
end

# ItemPickupEvent - event for when an item is picked up
class ItemPickupEvent
  include Drecs::Component
  component :item_id, :item_type, :value

  def initialize(item_id = nil, item_type = nil, value = 0)
    @item_id = item_id
    @item_type = item_type
    @value = value
  end
end

# MeleeAttackEvent - event fired when player performs a melee attack
# Contains attacker_id, target_x, target_y (tile coords), and damage
class MeleeAttackEvent
  include Drecs::Component
  component :attacker_id, :target_x, :target_y, :damage

  def initialize(attacker_id = nil, target_x = 0, target_y = 0, damage = 99)
    @attacker_id = attacker_id
    @target_x = target_x
    @target_y = target_y
    @damage = damage
  end
end

# AttackEvent - event for melee attacks (alternative naming)
class AttackEvent
  include Drecs::Component
  component :attacker_id, :target_id, :damage

  def initialize(attacker_id = nil, target_id = nil, damage = 0)
    @attacker_id = attacker_id
    @target_id = target_id
    @damage = damage
  end
end