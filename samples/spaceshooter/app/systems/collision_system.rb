class CollisionSystem
  def call(world, args)
    world.query(Position, Bullet) do |bullet_ids, bullet_positions, bullets|
      world.query(Position, Enemy, Sprite) do |enemy_ids, enemy_positions, enemies, enemy_sprites|
        Array.each_with_index(bullet_positions) do |bullet_pos, i|
          bullet_id = bullet_ids[i]

          Array.each_with_index(enemy_positions) do |enemy_pos, j|
            enemy_id = enemy_ids[j]
            enemy_sprite = enemy_sprites[j]

            if overlaps?(bullet_pos, 4, 12, enemy_pos, enemy_sprite.w, enemy_sprite.h)
              world.send_event(HitEvent.new(bullet_id, enemy_id))
            end
          end
        end
      end
    end
  end

  private

  def overlaps?(pos1, w1, h1, pos2, w2, h2)
    pos1.x < pos2.x + w2 &&
      pos1.x + w1 > pos2.x &&
      pos1.y < pos2.y + h2 &&
      pos1.y + h1 > pos2.y
  end
end
