# Tile component - tile type for dungeon tiles
class Tile < Struct.new(:type)
  # Tile type constants
  TILE_FLOOR = 0
  TILE_WALL = 1
  TILE_STAIRS_DOWN = 2
  TILE_STAIRS_UP = 3

  TILE_TYPES = [:floor, :wall, :stairs_down, :stairs_up].freeze

  def initialize(type = :floor)
    super(type)
  end

  def walkable?
    [TILE_FLOOR, TILE_STAIRS_DOWN, TILE_STAIRS_UP].include?(type)
  end

  def solid?
    type == TILE_WALL
  end

  def stairs?
    type == TILE_STAIRS_DOWN || type == TILE_STAIRS_UP
  end

  # Color mapping for rendering
  def self.color_for_type(tile_type)
    case tile_type
    when :floor, 0 then { r: 45, g: 45, b: 45 }           # Dark gray
    when :wall, 1 then { r: 74, g: 74, b: 74 }          # Medium gray
    when :stairs_down, 2 then { r: 147, g: 112, b: 219 } # Purple stairs down
    when :stairs_up, 3 then { r: 100, g: 149, b: 237 }   # Blue stairs up
    else { r: 45, g: 45, b: 45 }
    end
  end
end