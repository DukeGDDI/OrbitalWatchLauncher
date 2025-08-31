import "CoreLibs/graphics"
import "CoreLibs/keyboard"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local gfx <const> = playdate.graphics

-- ===== Screen =====
local screenW, screenH = 400, 240

-- ===== Config =====
local MIN_DISTANCE         = 15
local MAX_DISTANCE         = 250

local DISTANCE_SPEED       = 2.2     -- px/frame (Up/Down)
local CRANK_ANGLE_SENS     = 1.0     -- deg of reticle rotation per 1 deg crank change

local MISSILE_SPEED        = 4.0
local MISSILE_SIZE         = 2
local TRAIL_MAX_POINTS     = 30
local TRAIL_STEP           = 3

-- Explosion sprite tuning (collision-enabled)
local EXPLOSION_MAX_RADIUS = 22
local EXPLOSION_GROWTH     = 1.8
local EXPLOSION_Z          = 100     -- draw on top of primitives

local TARGET_CROSS         = 5

-- ===== State =====
local reticleAngle = 270
local reticleDistance = 60

local targets = {}        -- { {x=, y=} }
local missiles = {}       -- missiles are tables (primitives), explosions are sprites

-- ===== Utils =====
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ===== Explosion Sprite (instance-based, no metatable) =====
-- Creates a sprite, attaches fields, and defines s:update() inline.
local function newExplosion(x, y)
    local s = gfx.sprite.new()

    -- custom fields
    s.cx, s.cy = x, y
    s.r = 0
    s.maxR = EXPLOSION_MAX_RADIUS
    s.growth = EXPLOSION_GROWTH

    -- position & draw order
    s:moveTo(x, y)           -- center is (x,y)
    s:setZIndex(EXPLOSION_Z)

    -- start with a 1x1 image; we'll rebuild it as we grow
    local img = gfx.image.new(1, 1)
    s:setImage(img)
    s:setCollideRect(0, 0, 1, 1)

    -- per-frame growth + redraw + collision box sync
    function s:update()
        self.r += self.growth
        if self.r >= self.maxR then
            self:remove()
            return
        end

        local d = math.max(1, math.ceil(self.r * 2))

        -- redraw rings at new diameter
        local newImg = gfx.image.new(d, d)
        gfx.pushContext(newImg)
            gfx.drawCircleInRect(0, 0, d, d)
            local inner = math.floor(self.r * 0.6) * 2
            if inner > 2 then
                local inset = math.floor((d - inner) / 2)
                gfx.drawCircleInRect(inset, inset, inner, inner)
            end
        gfx.popContext()

        self:setImage(newImg)
        self:setCollideRect(0, 0, d, d)

        -- Example: detect overlaps (uncomment when you have other sprites)
        -- for _, other in ipairs(self:overlappingSprites()) do
        --     -- handle overlap with other
        -- end
    end

    s:add()
    return s
end





-- ===== Targets =====
local function markTarget(x, y)
    table.insert(targets, { x = x, y = y })
end

local function drawTargets()
    for _, t in ipairs(targets) do
        gfx.drawLine(t.x - TARGET_CROSS, t.y, t.x + TARGET_CROSS, t.y)
        gfx.drawLine(t.x, t.y - TARGET_CROSS, t.x, t.y + TARGET_CROSS)
    end
end

-- ===== Missiles (primitive, not sprites) =====
-- missile: { x,y, tx,ty, vx,vy, speed, trail={}, lastTrailX,lastTrailY }
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
        trail = {},
        lastTrailX = originX,
        lastTrailY = originY
    }
    table.insert(missiles, m)
end

local function updateMissiles()
    for i = #missiles, 1, -1 do
        local m = missiles[i]

        -- advance
        m.x += m.vx
        m.y += m.vy

        -- trail
        local dx, dy = (m.x - m.lastTrailX), (m.y - m.lastTrailY)
        if (dx*dx + dy*dy) >= (TRAIL_STEP * TRAIL_STEP) then
            table.insert(m.trail, { x = m.x, y = m.y })
            m.lastTrailX, m.lastTrailY = m.x, m.y
            if #m.trail > TRAIL_MAX_POINTS then
                table.remove(m.trail, 1)
            end
        end

        -- arrival?
        local txd, tyd = (m.tx - m.x), (m.ty - m.y)
        local dist2 = txd*txd + tyd*tyd
        if dist2 <= (m.speed * m.speed) then
            -- Snap to target
            m.x, m.y = m.tx, m.ty

            -- Remove matching target mark (±2px)
            for t = #targets, 1, -1 do
                if math.abs(targets[t].x - m.tx) < 2 and math.abs(targets[t].y - m.ty) < 2 then
                    table.remove(targets, t)
                    break
                end
            end

            -- Spawn explosion **sprite** (with collision)
            newExplosion(m.x, m.y)


            -- Remove missile (now handled visually by sprite)
            table.remove(missiles, i)
        end
    end
end

local function drawMissiles()
    for _, m in ipairs(missiles) do
        -- trail
        if #m.trail > 1 then
            for j = 2, #m.trail do
                local a, b = m.trail[j-1], m.trail[j]
                gfx.drawLine(a.x, a.y, b.x, b.y)
            end
        end
        -- tiny missile primitives
        gfx.fillCircleAtPoint(m.x, m.y, MISSILE_SIZE)
        gfx.drawLine(m.x, m.y, m.x + (m.vx * 2), m.y + (m.vy * 2))
    end
end

-- ===== Reticle (current mapping) =====
local function moveReticle()
    -- rotation via crank
    local crankDeltaDeg = playdate.getCrankChange()
    reticleAngle += crankDeltaDeg * CRANK_ANGLE_SENS

    -- distance via Up/Down
    if playdate.buttonIsPressed(playdate.kButtonUp) then
        reticleDistance += DISTANCE_SPEED
    elseif playdate.buttonIsPressed(playdate.kButtonDown) then
        reticleDistance -= DISTANCE_SPEED
    end
    reticleDistance = clamp(reticleDistance, MIN_DISTANCE, MAX_DISTANCE)

    -- polar -> cartesian
    local rad = math.rad(reticleAngle)
    local originX, originY = screenW/2, screenH
    local reticleX = originX + math.cos(rad) * reticleDistance
    local reticleY = originY + math.sin(rad) * reticleDistance

    -- guide & crosshair
    gfx.drawLine(originX, originY, reticleX, reticleY)
    local liveCross = 5
    gfx.drawLine(reticleX - liveCross, reticleY, reticleX + liveCross, reticleY)
    gfx.drawLine(reticleX, reticleY - liveCross, reticleX, reticleY + liveCross)

    return reticleX, reticleY
end

-- ===== Main Loop =====
function playdate.update()
    gfx.clear()

    -- Update & draw all explosion sprites (and any others)
    gfx.sprite.update()

    local x, y = moveReticle()

    -- LEFT: launch missile & mark
    if playdate.buttonJustPressed(playdate.kButtonLeft) then
        markTarget(x, y)
        launchMissile(x, y)
    end

    -- RIGHT: EMP / clear all markers
    if playdate.buttonJustPressed(playdate.kButtonRight) then
        targets = {}
    end

    updateMissiles()
    drawTargets()
    drawMissiles()
end