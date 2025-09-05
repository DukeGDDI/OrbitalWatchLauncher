-- main.lua
import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "scenes/gameplay"

local game = GamePlay.new()

function playdate.update()
    game:update()
end
