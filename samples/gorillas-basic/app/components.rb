component :acceleration, { x: 0, y: 0 }
component :animated, { enabled: false, idle_sprite: nil, index: 0, frame_tick_count: 0, frames: [] }
component :background_color, color: [33, 32, 87]
component :collides
component :empty
component :ephemeral
component :explodes
component :killable
component :labels, { labels: [] }
component :lines, { lines: [] }
component :owned, { owner: nil }
component :position, { x: 0, y: 0 }
component :rendered
component :rotation, { velocity: 20 }
component :score, { score: 0 }
component :size, { width: 0, height: 0 }
component :solid
component :solids, { solids: [] }
component :speed, { speed: 1 }
component :sprite, { path: nil, angle: 0 }
component :static_rendered, { rendered: false }
component :turn, { angle: "", angle_committed: false, first_player: nil, player: nil, velocity: "", velocity_committed: false }
component :debug
