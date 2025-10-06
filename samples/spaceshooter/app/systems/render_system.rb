class RenderSystem
  def call(world, args)
    args.outputs.solids << { x: 0, y: 0, w: 1280, h: 720, r: 0, g: 0, b: 20 }

    world.query(Position, Sprite) do |entity_ids, positions, sprites|
      Array.each_with_index(positions) do |pos, i|
        sprite = sprites[i]

        args.outputs.solids << {
          x: pos.x,
          y: pos.y,
          w: sprite.w,
          h: sprite.h,
          r: sprite.r,
          g: sprite.g,
          b: sprite.b,
          a: sprite.a
        }
      end
    end
  end
end
