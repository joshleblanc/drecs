class Renderable < Struct.new(:layer)
  LAYERS = {
    tile: 0,
    item: 1,
    enemy: 2,
    player: 3,
    ui: 4
  }.freeze

  def initialize(layer = 1)
    super(layer)
  end

  def self.tile_layer
    Renderable.new(LAYERS[:tile])
  end

  def self.item_layer
    Renderable.new(LAYERS[:item])
  end

  def self.enemy_layer
    Renderable.new(LAYERS[:enemy])
  end

  def self.player_layer
    Renderable.new(LAYERS[:player])
  end

  def self.ui_layer
    Renderable.new(LAYERS[:ui])
  end
end