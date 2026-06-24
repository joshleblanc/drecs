# TurnSystem - manages turn-based game flow
# Turn phases:
#   :player_input - Player can take one action (move or attack)
#   :enemy_turn - Enemies are taking their actions
class TurnSystem
  def call(world, args)
    turn_state = world.resource(:turn_state)
    return unless turn_state

    case turn_state[:phase]
    when :player_input
      # Check if player has acted (moved or attacked)
      if turn_state[:player_acted]
        # Transition to enemy turn
        turn_state[:phase] = :enemy_turn
      end
    when :enemy_turn
      # Only transition back after enemies have acted
      if turn_state[:enemy_acted]
        turn_state[:phase] = :player_input
        turn_state[:player_acted] = false
        turn_state[:enemy_acted] = false
      end
    end
  end
end