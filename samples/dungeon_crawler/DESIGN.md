# Dungeon Crawler ECS Sample - Game Design Document

## Overview

A classic roguelike dungeon crawler with procedurally generated rooms, strategic combat, and resource management. The player navigates through dungeon floors, defeats enemies, collects loot, and finds the exit to descend deeper. Death is permanent — one life, one chance.

**Core Loop:** Explore rooms → Fight enemies → Collect items → Find stairs → Repeat

---

## Game Mechanics

### Player
- **Movement:** Grid-based or tile-based (cell size: 32px)
- **Health:** Starts at 100, max 100. Health pickups restore HP.
- **Attack:** Melee attack in facing direction (sword swing)
- **Keys:** Collect keys to unlock doors between rooms
- **Score:** Points for killing enemies and collecting gold

### Dungeon Structure

#### Floor
- A floor consists of **5-8 rooms** connected by doorways
- One room contains the **stairs down** (exit to next floor)
- Some rooms contain **locked doors** requiring keys
- Rooms are procedurally arranged in a connected graph

#### Room
- Fixed tile grid: **20x15 tiles** (640x480 effective area)
- Walls form the perimeter
- Internal walls/obstacles create tactical cover
- 1-4 **doorways** connect to adjacent rooms
- Spawns enemies and loot on room entry

#### Tiles
| Tile | Description | Walkable |
|------|-------------|----------|
| Floor | Basic traversable tile | Yes |
| Wall | Solid obstacle | No |
| Door | Locked barrier (needs key) | No (until unlocked) |
| Doorway | Open passage between rooms | Yes |
| Stairs | Exit to next floor | Yes |

### Enemies

#### Goblin (Basic)
- **HP:** 30
- **Damage:** 10 per hit
- **Behavior:** Moves toward player when in line of sight
- **Speed:** Slow (1 tile per 2 ticks)
- **AI:** Simple pathfinding toward player

#### Skeleton (Ranged)
- **HP:** 20
- **Damage:** 8 per hit (ranged)
- **Behavior:** Maintains distance, shoots projectiles
- **Attack Range:** 5 tiles
- **Speed:** Medium (1 tile per 1.5 ticks)

#### Orc (Tank)
- **HP:** 80
- **Damage:** 25 per hit
- **Behavior:** Charges at player, brief wind-up animation
- **Speed:** Slow but fast burst
- **Special:** Knockback on hit

### Items

#### Health Potion
- Restores **25 HP**
- Visual: Red bottle
- Spawns in rooms, limited quantity

#### Key
- Unlocks one locked door
- Visual: Golden key
- Some rooms have 1-2 keys

#### Gold Pile
- Adds **10 points** to score
- Visual: Yellow pile
- Enemies drop on death

#### Weapon Upgrade (Future)
- Increases attack damage
- Visual: Sword with glow

### Combat System

- **Turn-based movement:** Player moves, then all enemies move
- **Attack:** Player attacks adjacent tile in facing direction
- **Enemy attack:** Enemies attack when adjacent to player
- **Hit detection:** Adjacent tiles (4-directional or 8-directional)
- **Damage calculation:** Base damage ± random variance

---

## ECS Architecture

### Component Types

#### Position
```ruby
Position = Struct.new(:x, :y)  # Tile coordinates
```

#### Velocity (for smooth movement transitions)
```ruby
Velocity = Struct.new(:dx, :dy)  # Pixel offset
```

#### Tile
```ruby
Tile = Struct.new(:type)  # :floor, :wall, :door, :doorway, :stairs
```

#### Health
```ruby
Health = Struct.new(:current, :max)
```

#### Sprite
```ruby
Sprite = Struct.new(:w, :h, :r, :g, :b, :a)
```

#### Player (tag)
```ruby
Player = Struct.new(:facing_direction, :attack_cooldown)
```

#### Enemy (tag)
```ruby
Enemy = Struct.new(:type, :damage, :hp, :attack_cooldown)
# type: :goblin, :skeleton, :orc
```

#### Projectile
```ruby
Projectile = Struct.new(:dx, :dy, :damage, :owner_id)
```

#### Item
```ruby
Item = Struct.new(:type, :value)
# type: :health, :key, :gold
```

#### Collider
```ruby
Collider = Struct.new(:radius)
```

#### Renderable (tag for visible entities)
```ruby
Renderable = Struct.new(:layer)
```

#### Destroyed (marker for cleanup)
```ruby
Destroyed = Struct.new
```

### Bundles

```ruby
PLAYER_BUNDLE = Drecs.bundle(Position, Velocity, Health, Sprite, Collider, Renderable, Player)
ENEMY_BUNDLE = Drecs.bundle(Position, Velocity, Health, Sprite, Collider, Renderable, Enemy)
PROJECTILE_BUNDLE = Drecs.bundle(Position, Velocity, Sprite, Collider, Renderable, Projectile)
ITEM_BUNDLE = Drecs.bundle(Position, Sprite, Renderable, Item)
TILE_BUNDLE = Drecs.bundle(Tile)
```

### Systems

#### InputSystem
- **Query:** Player, Position
- **Filter:** Player's turn
- **Action:** Read keyboard, update velocity based on direction
- **Triggers:** Move attempt → MovementSystem

#### MovementSystem
- **Query:** Position, Velocity
- **Action:** Apply velocity to position, clamp to tile grid
- **Handles:** Collision with walls, door interaction

#### EnemyAISystem
- **Query:** Enemy, Position, Health
- **Filter:** Enemies' turn
- **Action:** Each enemy type AI:
  - Goblin: Move toward player if in range
  - Skeleton: Maintain distance, fire projectile
  - Orc: Charge if close, else idle

#### CombatSystem
- **Query:** Player, Position
- **Action:** Check for attack input, apply damage to adjacent enemy
- **Triggers:** HitEvent on damage dealt

#### ProjectileSystem
- **Query:** Projectile, Position
- **Action:** Move projectiles, check collisions with Player/Enemy
- **Triggers:** HitEvent, destroy projectile on hit

#### PickupSystem
- **Query:** Player, Position, Item
- **Action:** Check overlap, apply item effect, remove from world
- **Effects:** Heal player, add key to inventory, add score

#### RenderSystem
- **Query:** Tile (layer 0), Sprite (layer 1), Enemy (layer 2), Player (layer 3), UI (layer 4)
- **Action:** Draw all renderables in layer order

#### TurnSystem
- **Action:** Toggle turn between Player and Enemies
- **Triggers:** After player moves or all enemies acted

### Events

```ruby
MoveEvent = Struct.new(:entity_id, :from_x, :from_y, :to_x, :to_y)
AttackEvent = Struct.new(:attacker_id, :target_id, :damage)
HitEvent = Struct.new(:target_id, :damage, :source)
DeathEvent = Struct.new(:entity_id, :killer_id)
PickupEvent = Struct.new(:entity_id, :item_type, :value)
KeyUsedEvent = Struct.new(:entity_id, :door_x, :door_y)
```

### Resources

```ruby
GameState = Struct.new(:floor, :score, :game_over)
TurnState = Struct.new(:current_turn)  # :player or :enemies
Inventory = Struct.new(:keys, :health_potions)
DungeonLevel = Struct.new(:rooms, :current_room, :grid)
```

---

## User Interface

### HUD
- **Health Bar:** Top-left, red fill on dark background
- **Score:** Top-right, white text
- **Floor:** Top-center, "Floor X"
- **Keys:** Below floor, key icons
- **Turn Indicator:** Bottom-center, "Your Turn" / "Enemy Turn"

### Game Over Screen
- Dark overlay
- "YOU DIED" in red
- Final score display
- "Press R to restart"

### Victory Screen (Reaching Floor 5)
- "ESCAPED!" in gold
- Total score and floors cleared

---

## Technical Implementation

### Dungeon Generation Algorithm
1. Create graph of 5-8 room nodes
2. Connect nodes ensuring all reachable from start
3. Assign room types: start, normal, key-required, boss (floor 5)
4. Generate tile grid for each room
5. Place doorways at graph edges
6. Spawn enemies based on room difficulty
7. Place items (health, keys) randomly

### Room Types
| Type | Enemies | Items | Special |
|------|---------|-------|---------|
| Start | 0 | 1-2 health | Player spawns here |
| Normal | 2-3 | 1 health or key | - |
| Key Room | 2-3 | 1 key | Locked door to stairs |
| Boss | 1 orc + 2 goblins | Gold piles | Only on floor 5 |

### Turn Flow
```
1. Player Input (WASD/Arrows)
2. Player Move → Collision Check
3. Player Attack Check (Space)
4. Enemy Turn
   - For each enemy (in spawn order):
     - AI Decision
     - Enemy Move
     - Enemy Attack (if adjacent)
5. Projectile Movement
6. Pickup Check
7. Death Check
8. Turn Toggle
9. Render
```

### ECS Query Examples

```ruby
# Get all enemies
world.query(Enemy, Position, Health)

# Get items on current tile
world.each_entity(Item, Position, with: Renderable) do |id, item, pos|
  next unless pos.x == player_pos.x && pos.y == player_pos.y
end

# Get all tiles in room
world.query(Tile, Position)

# Get projectiles
world.query(Projectile, Position, Velocity)
```

---

## Visual Style

### Color Palette
| Element | Color |
|---------|-------|
| Floor | #2D2D2D (dark gray) |
| Wall | #4A4A4A (medium gray) |
| Player | #4A90D9 (blue) |
| Goblin | #50C878 (green) |
| Skeleton | #F5F5DC (bone white) |
| Orc | #8B4513 (brown) |
| Health Potion | #DC143C (crimson) |
| Key | #FFD700 (gold) |
| Gold | #DAA520 (goldenrod) |
| Stairs | #9370DB (purple) |

### Sprite Sizes
- Player: 28x28
- Enemies: 24x24
- Items: 16x16
- Tiles: 32x32

---

## Feature Scope

### Phase 1 (Core MVP)
- [x] Grid-based dungeon
- [x] Player movement (4-directional)
- [x] Basic enemies (Goblin only)
- [x] Turn-based combat
- [x] Health system
- [x] Room transitions
- [x] Stairs progression
- [x] Game over / restart

### Phase 2 (Full Release)
- [ ] Multiple enemy types
- [ ] Keys and locked doors
- [ ] Items (health, gold)
- [ ] Score system
- [ ] Floor counter
- [ ] Multiple floors (5 floors to escape)

### Phase 3 (Polish)
- [ ] Skeleton ranged enemy
- [ ] Orc boss enemy
- [ ] Enemy death drops
- [ ] Sound effects
- [ ] Tile variety / textures

---

## Controls

| Key | Action |
|-----|--------|
| W / Up Arrow | Move up |
| S / Down Arrow | Move down |
| A / Left Arrow | Move left |
| D / Right Arrow | Move right |
| Space | Attack |
| R | Restart (game over) |

---

## Success Criteria

1. **Playable:** Player can move, attack, die, and restart
2. **Complete:** All 5 floors can be cleared
3. **Showcases ECS:** Clearly demonstrates drecs features in action
4. **Performance:** 60 FPS with 50+ entities on screen
5. **Readable:** Code is well-commented and educational