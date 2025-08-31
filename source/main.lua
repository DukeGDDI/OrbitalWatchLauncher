import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local gfx <const> = playdate.graphics

-- screen dimensions
local screenW, screenH = 400, 240

-- ========= Config =========
local MIN_DISTANCE       = 15
local MAX_DISTANCE       = 250
local ROTATE_SPEED       = 5              -- deg/frame
local CRANK_SENSITIVITY  = 0.35           -- px per crank degree

local MISSILE_SPEED      = 4.0            -- px/frame
local MISSILE_SIZE       = 2              -- px (visual)
local TRAIL_MAX_POINTS   = 30             -- stored trail vertices per missile
local TRAIL_STEP         = 3              -- add a new trail point every N px traveled

local EXPLOSION_MAX_RADIUS = 22           -- px (configurable explosion radius)
local EXPLOSION_GROWTH     = 1.8          -- px/frame

-- ========= State =========
local reticleAngle = 270
local reticleDistance = 60

local TARGET_CROSS = 5
local targets = {}        -- { {x=, y=} ... }

-- missiles: each is
-- { x, y, tx, ty, vx, vy, speed, state="flying"|"exploding", explosionR, trail={ {x,y}... }, lastTrailX, lastTrailY }
local missiles = {}

-- ========= Helpers =========
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ========= Target Marking =========
local function markTarget(x, y)
    table.insert(targets, { x = x, y = y })
end

local function drawTargets()
    for _, t in ipairs(targets) do
        gfx.drawLine(t.x - TARGET_CROSS, t.y, t.x + TARGET_CROSS, t.y)
        gfx.drawLine(t.x, t.y - TARGET_CROSS, t.x, t.y + TARGET_CROSS)
    end
end

-- ========= Missile System =========
-- ========= Missile System =========
local function launchMissile(targetX, targetY)
    local originX, originY = screenW/2, screenH
    local dx, dy = (targetX - originX), (targetY - originY)
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.001 then return end

    local vx = (dx / len) * MISSILE_SPEED
    local vy = (dy / len) * MISSILE_SPEED

    local m = {
        x = originX, y = originY,
        tx = targetX, ty = targetY,
        vx = vx, vy = vy,
        speed = MISSILE_SPEED,
        state = "flying",
        explosionR = 0,
        trail = {},
        lastTrailX = originX,
        lastTrailY = originY
    }
    table.insert(missiles, m)
end

local function updateMissiles()
    for i = #missiles, 1, -1 do
        local m = missiles[i]

        if m.state == "flying" then
            -- advance missile
            m.x += m.vx
            m.y += m.vy

            -- add to trail
            local dx, dy = (m.x - m.lastTrailX), (m.y - m.lastTrailY)
            if (dx*dx + dy*dy) >= (TRAIL_STEP * TRAIL_STEP) then
                table.insert(m.trail, { x = m.x, y = m.y })
                m.lastTrailX, m.lastTrailY = m.x, m.y
                if #m.trail > TRAIL_MAX_POINTS then
                    table.remove(m.trail, 1)
                end
            end

            -- check arrival at target
            local toTargetX, toTargetY = (m.tx - m.x), (m.ty - m.y)
            local dist2 = toTargetX*toTargetX + toTargetY*toTargetY
            if dist2 <= (m.speed * m.speed) then
                m.x, m.y = m.tx, m.ty
                m.state = "exploding"
                m.explosionR = 0

                -- remove the target mark at this coordinate
                for t = #targets, 1, -1 do
                    if math.abs(targets[t].x - m.tx) < 2 and math.abs(targets[t].y - m.ty) < 2 then
                        table.remove(targets, t)
                        break
                    end
                end
            end

        elseif m.state == "exploding" then
            m.explosionR += EXPLOSION_GROWTH
            if m.explosionR >= EXPLOSION_MAX_RADIUS then
                table.remove(missiles, i) -- remove missile after explosion
            end
        end
    end
end


local function drawMissiles()
    for _, m in ipairs(missiles) do
        if m.state == "flying" then
            -- trail (polyline)
            if #m.trail > 1 then
                for j = 2, #m.trail do
                    local a, b = m.trail[j-1], m.trail[j]
                    gfx.drawLine(a.x, a.y, b.x, b.y)
                end
            end
            -- tiny missile body (primitive): a small filled circle + nose line
            gfx.fillCircleAtPoint(m.x, m.y, MISSILE_SIZE)
            gfx.drawLine(m.x, m.y, m.x + (m.vx * 2), m.y + (m.vy * 2))

        elseif m.state == "exploding" then
            -- expanding ring explosion
            gfx.drawCircleAtPoint(m.x, m.y, m.explosionR)
            -- optional: inner ring for style
            if m.explosionR > 6 then
                gfx.drawCircleAtPoint(m.x, m.y, m.explosionR * 0.6)
            end
        end
    end
end

-- ========= Reticle =========
local function moveReticle()
    -- range via relative crank delta
    local crankDeltaDeg = playdate.getCrankChange()
    reticleDistance += crankDeltaDeg * CRANK_SENSITIVITY
    reticleDistance = clamp(reticleDistance, MIN_DISTANCE, MAX_DISTANCE)

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

-- ========= Main Loop =========
function playdate.update()
    gfx.clear()

    local x, y = moveReticle()

    -- Up: mark + launch
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        markTarget(x, y)
        launchMissile(x, y)
    end

    -- Down: clear all markers and missiles (optional)
    if playdate.buttonJustPressed(playdate.kButtonDown) then
        targets = {}
        missiles = {}
    end

    updateMissiles()
    drawTargets()
    drawMissiles()
end
