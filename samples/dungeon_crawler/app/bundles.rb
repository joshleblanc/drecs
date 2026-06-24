require_relative 'components/position'
require_relative 'components/velocity'
require_relative 'components/health'
require_relative 'components/sprite'
require_relative 'components/collider'
require_relative 'components/renderable'
require_relative 'components/player'
require_relative 'components/enemy'
require_relative 'components/item'
require_relative 'components/tile'

PLAYER_BUNDLE = Drecs.bundle(Position, Velocity, Health, Sprite, Collider, Renderable, Player)
ENEMY_BUNDLE = Drecs.bundle(Position, Velocity, Health, Sprite, Collider, Renderable, Enemy)
ITEM_BUNDLE = Drecs.bundle(Position, Sprite, Renderable, Item)
TILE_BUNDLE = Drecs.bundle(Tile, Position, Sprite, Renderable)