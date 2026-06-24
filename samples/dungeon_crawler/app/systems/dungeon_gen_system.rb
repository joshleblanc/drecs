# DungeonGenSystem - Generates multi-room dungeons with corridors, stairs, and items
# Creates connected rooms, corridors, and places treasure/stairs
class DungeonGenSystem
  ROOM_WIDTH = 7
  ROOM_HEIGHT = 7
  TILE_SIZE = 32
  DUNGEON_WIDTH = ROOM_WIDTH + 2
  DUNGEON_HEIGHT = ROOM_HEIGHT + 2
  
  # Tile types
  TILE_FLOOR = 0
  TILE_WALL = 1
  TILE_STAIRS_DOWN = 2
  TILE_STAIRS_UP = 3
  
  def self.generate_dungeon(world, floor: 1)
    system = new
    system.instance_variable_set(:@floor, floor)
    system.call(world, nil)
  end

  def call(world, args)
    dungeon = world.resource(:dungeon)
    return if dungeon && dungeon[:generated]

    dungeon_data = generate_multi_room_dungeon
    world.insert_resource(:dungeon, dungeon_data)
    
    # Spawn initial goblins and items
    spawn_goblins(world, dungeon_data)
    spawn_items(world, dungeon_data)
    
    # Place stairs if not on floor 1
    if @floor > 1
      place_stairs_up(world, dungeon_data)
    end
  end

  private

  def generate_multi_room_dungeon
    # 21x21 grid for bigger dungeon (7x7 rooms with corridors)
    @width = 21
    @height = 21
    @dungeon = Array.new(@height) { Array.new(@width, TILE_WALL) }
    
    # Room positions (center of each room in a 3x3 grid)
    room_positions = [
      { x: 3, y: 3, w: 7, h: 7 },   # top-left
      { x: 11, y: 3, w: 7, h: 7 },  # top-right
      { x: 3, y: 11, w: 7, h: 7 },  # bottom-left
      { x: 11, y: 11, w: 7, h: 7 }, # bottom-right
      { x: 7, y: 7, w: 7, h: 7 },   # center (larger room)
    ]
    
    # Carve out rooms
    room_positions.each do |room|
      carve_room(room[:x], room[:y], room[:w], room[:h])
    end
    
    # Connect rooms with corridors
    connect_rooms(
      { x: 6, y: 6 },   # center room left door
      { x: 3, y: 6 }    # top-left room right door
    )
    connect_rooms(
      { x: 8, y: 6 },   # center room right door
      { x: 14, y: 6 }   # top-right room left door
    )
    connect_rooms(
      { x: 6, y: 10 },  # center room bottom-left door
      { x: 3, y: 10 }   # bottom-left room top door
    )
    connect_rooms(
      { x: 8, y: 10 },  # center room bottom-right door
      { x: 14, y: 10 }  # bottom-right room top door
    )
    
    # Find floor positions for spawning
    floor_positions = []
    (0...@height).each do |y|
      (0...@width).each do |x|
        floor_positions << { x: x, y: y } if @dungeon[y][x] == TILE_FLOOR
      end
    end
    
    {
      dungeon: @dungeon,
      floor_positions: floor_positions,
      width: @width,
      height: @height,
      tile_size: TILE_SIZE,
      generated: true,
      floor: @floor
    }
  end

  def carve_room(x, y, w, h)
    (y...y+h).each do |ry|
      (x...x+w).each do |rx|
        @dungeon[ry][rx] = TILE_FLOOR if inside_dungeon?(rx, ry)
      end
    end
  end

  def connect_rooms(from, to)
    # L-shaped corridor
    x, y = from[:x], from[:y]
    target_x, target_y = to[:x], to[:y]
    
    # Horizontal first
    while x != target_x
      @dungeon[y][x] = TILE_FLOOR if inside_dungeon?(x, y)
      x += (target_x > x) ? 1 : -1
    end
    # Then vertical
    while y != target_y
      @dungeon[y][x] = TILE_FLOOR if inside_dungeon?(x, y)
      y += (target_y > y) ? 1 : -1
    end
  end

  def inside_dungeon?(x, y)
    x >= 0 && x < @width && y >= 0 && y < @height
  end

  def spawn_goblins(world, dungeon_data)
    goblin_count = 4 + @floor  # More goblins on deeper floors
    
    floor_positions = dungeon_data[:floor_positions].reject do |pos|
      pos[:x] >= 6 && pos[:x] <= 8 && pos[:y] >= 6 && pos[:y] <= 8
    end
    
    shuffled = floor_positions.shuffle
    goblin_positions = shuffled.take([goblin_count, shuffled.length].min)
    
    goblin_positions.each_with_index do |pos, index|
      pixel_x = pos[:x] * TILE_SIZE + TILE_SIZE / 2
      pixel_y = pos[:y] * TILE_SIZE + TILE_SIZE / 2
      
      enemy_id = world.spawn(
        Position.new(pixel_x, pixel_y),
        Velocity.new((rand - 0.5) * 0.5, (rand - 0.5) * 0.5),
        Health.new(20 + @floor * 10, 20 + @floor * 10),
        Sprite.new(28, 28, 255, 80, 80),
        Collider.new(14),
        Enemy.new(:goblin, 5 + @floor * 2, 20 + @floor * 10, 0, 200)
      )
      
      world.name(enemy_id, "Goblin_#{index + 1}")
    end
  end

  def spawn_items(world, dungeon_data)
    floor_positions = dungeon_data[:floor_positions]
    
    # Gold piles (3-5 per floor)
    gold_count = 3 + rand(3)
    gold_positions = floor_positions.shuffle.take(gold_count)
    gold_positions.each_with_index do |pos, index|
      pixel_x = pos[:x] * TILE_SIZE + TILE_SIZE / 2
      pixel_y = pos[:y] * TILE_SIZE + TILE_SIZE / 2
      
      world.spawn(
        Position.new(pixel_x, pixel_y),
        Sprite.new(16, 16, 255, 215, 0),  # Gold color
        Item.new(:gold, 10 + rand(20) + @floor * 5)
      )
    end
    
    # Health potions (1-2 per floor)
    potion_count = 1 + rand(2)
    potion_positions = floor_positions.reject { |p| gold_positions.include?(p) }.shuffle.take(potion_count)
    potion_positions.each do |pos|
      pixel_x = pos[:x] * TILE_SIZE + TILE_SIZE / 2
      pixel_y = pos[:y] * TILE_SIZE + TILE_SIZE / 2
      
      world.spawn(
        Position.new(pixel_x, pixel_y),
        Sprite.new(16, 16, 255, 100, 100),  # Red for potion
        Item.new(:potion, 20)
      )
    end
  end

  def place_stairs_up(world, dungeon_data)
    # Place stairs in center room
    stair_x, stair_y = 7, 7
    
    # Find nearest floor tile
    floor_positions = dungeon_data[:floor_positions]
    nearest = floor_positions.min_by do |pos|
      (pos[:x] - stair_x).abs + (pos[:y] - stair_y).abs
    end
    
    if nearest
      pixel_x = nearest[:x] * TILE_SIZE + TILE_SIZE / 2
      pixel_y = nearest[:y] * TILE_SIZE + TILE_SIZE / 2
      
      world.spawn(
        Position.new(pixel_x, pixel_y),
        Sprite.new(28, 28, 147, 112, 219),  # Purple stairs
        Item.new(:stairs_up, 0)
      )
    end
  end
end