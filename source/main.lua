import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local gfx <const> = playdate.graphics

-- screen dimensions
local screenW, screenH = 400, 240

-- reticle configuration
local MIN_DISTANCE = 15
local MAX_DISTANCE = 250
local ROTATE_SPEED = 5
local CRANK_SENSITIVITY = 0.35

-- reticle state
local reticleAngle = 270
local reticleDistance = 60

-- target markers
local TARGET_CROSS = 5
local targets = {}   -- holds {x=..., y=...}

-- Leave behind a persistent "+" marker at (x, y)
local function markTarget(x, y)
    table.insert(targets, { x = x, y = y })
end

-- Draw all saved "+" markers
local function drawTargets()
    for _, t in ipairs(targets) do
        gfx.drawLine(t.x - TARGET_CROSS, t.y, t.x + TARGET_CROSS, t.y)
        gfx.drawLine(t.x, t.y - TARGET_CROSS, t.x, t.y + TARGET_CROSS)
    end
end

-- Updates inputs, clamps, draws live reticle, returns its current position
local function moveReticle()
    -- range via relative crank delta
    local crankDeltaDeg = playdate.getCrankChange()
    reticleDistance += crankDeltaDeg * CRANK_SENSITIVITY
    if reticleDistance < MIN_DISTANCE then reticleDistance = MIN_DISTANCE end
    if reticleDistance > MAX_DISTANCE then reticleDistance = MAX_DISTANCE end

    -- angle via dpad
    if playdate.buttonIsPressed(playdate.kButtonLeft) then
        reticleAngle -= ROTATE_SPEED
    elseif playdate.buttonIsPressed(playdate.kButtonRight) then
        reticleAngle += ROTATE_SPEED
    end

    -- polar -> cartesian
    local rad = math.rad(reticleAngle)
    local originX, originY = screenW/2, screenH
    local reticleX = originX + math.cos(rad) * reticleDistance
    local reticleY = originY + math.sin(rad) * reticleDistance

    -- draw guide line and live crosshair
    gfx.drawLine(originX, originY, reticleX, reticleY)
    local liveCross = 5
    gfx.drawLine(reticleX - liveCross, reticleY, reticleX + liveCross, reticleY)
    gfx.drawLine(reticleX, reticleY - liveCross, reticleX, reticleY + liveCross)

    return reticleX, reticleY
end

function playdate.update()
    gfx.clear()

    local x, y = moveReticle()

    -- Press Up to leave a persistent "+" at the current reticle position
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        markTarget(x, y)
    end

    -- (Optional) Press Down to clear all markers
    if playdate.buttonJustPressed(playdate.kButtonDown) then
        targets = {}
    end

    -- Draw saved markers on top
    drawTargets()
end
