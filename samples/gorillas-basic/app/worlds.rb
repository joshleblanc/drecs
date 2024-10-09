include Drecs::Main

world(:game,
  systems: [
    :render_background,
    :generate_stage,
    :render_scores,
    :render_static_solids,
    :update_wind,
    :handle_rotation,
    :render_lines,
    :render_solids,
    :render_labels,
    :accelerate,
    :update_acceleration,
    :handle_explosion,
    :handle_miss,
    :cleanup_destroyed,
    :render_sprites,
    :render_animations,
    :handle_input,
    :render_turn_input,
    :check_win,
    :handle_next_turn
  ],
  entities: [
    :background,
    :scoreboard,
    {current_turn: {as: :current_turn}},
    {wind: {as: :wind}},
    {gravity: {as: :gravity}},
    {gorilla: {as: :player_one, animated: {idle_sprite: "sprites/left-idle.png", frames: [[5, "sprites/left-0.png"], [5, "sprites/left-1.png"], [5, "sprites/left-2.png"]]}}},
    {gorilla: {as: :player_two, animated: {idle_sprite: "sprites/right-idle.png", frames: [[5, "sprites/right-0.png"], [5, "sprites/right-1.png"], [5, "sprites/right-2.png"]]}}}
  ])
