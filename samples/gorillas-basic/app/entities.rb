include Drecs::Main

entity :background, :background_color
entity :banana, :acceleration, :collides, :owned, :position, :rendered, :rotation, size: {width: 15, height: 15}, sprite: {path: "samples/gorillas-basic/sprites/banana.png"}
entity :building, :ephemeral, :explodes, :position, :size, :solid, :solids, :static_rendered
entity :current_turn, :turn
entity :game_over_screen, :ephemeral, :rendered, :solids, labels: {labels: [[640, 370, "Game Over!!", 5, 1, FANCY_WHITE.values]]}
entity :gorilla, :animated, :explodes, :killable, :position, :score, :solid, size: {width: 50, height: 50}
entity :gravity, speed: {speed: 0.25}
entity :scoreboard, :debug, :rendered, :solid, position: {x: 0, y: 0}, size: {width: 1200, height: 31}, solids: {solids: [[0, 0, 1280, 31, FANCY_WHITE.values], [1, 1, 1279, 29]]}
entity :wind, :rendered, :solids, :speed, lines: {lines: [640, 30, 640, 0, FANCY_WHITE.values]}
entity :hole, :empty, :ephemeral, :position, :rendered, size: {width: 40, height: 40}, sprite: {path: "samples/gorillas-basic/sprites/hole.png"}, animated: {enabled: true, frames: [[3, "samples/gorillas-basic/sprites/explosion0.png"], [3, "samples/gorillas-basic/sprites/explosion1.png"], [3, "samples/gorillas-basic/sprites/explosion2.png"], [3, "samples/gorillas-basic/sprites/explosion3.png"], [3, "samples/gorillas-basic/sprites/explosion4.png"], [3, "samples/gorillas-basic/sprites/explosion5.png"], [3, "samples/gorillas-basic/sprites/explosion6.png"]]}
