-- main.lua
import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "scenes/gameplay"
import "scenes/splash"

local game = GamePlay.new({
    MISSILE_SPEED = 5.5,
    ENEMY_SPAWN_RATE = 0.04,
    TARGET_CROSS = 7,
    EXPLOSION_MAX_RADIUS = 28,
})
local gfx <const> = playdate.graphics
local splashImage = gfx.image.new("images/launchImage.png") -- load the image

function playdate.update()
    if playdate.isCrankDocked() then
        if splashImage then
            splashImage:draw(0, 0) -- draw at top-left corner
        end
        playdate.ui.crankIndicator:draw()
    else
        game:update()
    end
end
