-- main.lua
import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "scenes/gameplay"

local game = GamePlay.new({
    MISSILE_SPEED = 5.5,
    ENEMY_SPAWN_RATE = 0.04,
    TARGET_CROSS = 7,
    EXPLOSION_MAX_RADIUS = 28,
})

function playdate.update()
    game:update()
end
