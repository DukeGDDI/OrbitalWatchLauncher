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

-- Enemy Missile Config
local ENEMY_MISSILE_SPEED   = 1.5   -- px/frame (slightly slower than player)
local ENEMY_TRAIL_MAX_POINTS= 30
local ENEMY_TRAIL_STEP      = 3
local ENEMY_MISSILE_SIZE    = 2
local ENEMY_SPAWN_RATE      = 0.02


-- ===== State =====
local reticleAngle = 270
local reticleDistance = 60
local currentReticleX, currentReticleY = 0, 0


local targets = {}        -- { {x=, y=} }
local missiles = {}       -- missiles are tables (primitives), explosions are sprites
local enemies = {}   -- enemy missiles (same structure as player missiles)
local explosions = {}  -- holds active explosion sprites we create


-- Forward declaration so functions defined above can call it
local newExplosion

-- ===== Utils =====
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function pruneExplosions()
    for i = #explosions, 1, -1 do
        if explosions[i].__dead then
            table.remove(explosions, i)
        end
    end
end

-- Launch an enemy missile from top (xOrigin, 0) to ground (xTarget, screenH)
local function launchEnemyMissile(xOrigin, xTarget)
    -- clamp to screen so we don't spawn off-screen
    xOrigin = clamp(xOrigin, 0, screenW)
    xTarget = clamp(xTarget, 0, screenW)

    local originX, originY = xOrigin, 0
    local targetX, targetY = xTarget, screenH

    local dx, dy = (targetX - originX), (targetY - originY)
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.001 then return end

    local vx = (dx / len) * ENEMY_MISSILE_SPEED
    local vy = (dy / len) * ENEMY_MISSILE_SPEED

    local e = {
        x = originX, y = originY,
        tx = targetX, ty = targetY,
        vx = vx, vy = vy,
        speed = ENEMY_MISSILE_SPEED,
        trail = {},
        lastTrailX = originX,
        lastTrailY = originY
    }
    table.insert(enemies, e)
end

local function updateEnemies()
    -- (optionally clear out finished explosion refs first)
    pruneExplosions()

    for i = #enemies, 1, -1 do
        local e = enemies[i]

        -- advance
        e.x += e.vx
        e.y += e.vy

        -- trail (same style)
        local dx, dy = (e.x - e.lastTrailX), (e.y - e.lastTrailY)
        if (dx*dx + dy*dy) >= (ENEMY_TRAIL_STEP * ENEMY_TRAIL_STEP) then
            table.insert(e.trail, { x = e.x, y = e.y })
            e.lastTrailX, e.lastTrailY = e.x, e.y
            if #e.trail > ENEMY_TRAIL_MAX_POINTS then
                table.remove(e.trail, 1)
            end
        end

        -- **Explosion overlap check** — detonate enemy if inside any player explosion
        local destroyedByExplosion = false
        for _, ex in ipairs(explosions) do
            if not ex.__dead then
                local exdx, exdy = e.x - ex.cx, e.y - ex.cy
                if (exdx*exdx + exdy*exdy) <= (ex.r * ex.r) then
                    -- Enemy enters blast radius: explode enemy here
                    newExplosion(e.x, e.y)
                    table.remove(enemies, i)
                    destroyedByExplosion = true
                    break
                end
            end
        end
        if destroyedByExplosion then
            goto continue_enemy_loop
        end

        -- arrival at ground?
        local txd, tyd = (e.tx - e.x), (e.ty - e.y)
        local dist2 = txd*txd + tyd*tyd
        if dist2 <= (e.speed * e.speed) then
            e.x, e.y = e.tx, e.ty
            newExplosion(e.x, e.y)  -- ground impact explosion
            table.remove(enemies, i)
        end

        ::continue_enemy_loop::
    end
end

local function randomSpawnEnemyMissile()
     if math.random() < ENEMY_SPAWN_RATE then  -- % per frame while held
        launchEnemyMissile(math.random(0, screenW), math.random(40, screenW-40))
    end
end


-- ===== Explosion Sprite (instance-based, no metatable) =====
-- Creates a sprite, attaches fields, and defines s:update() inline.
newExplosion = function(x, y)
    local s = gfx.sprite.new()

    -- custom fields
    s.cx, s.cy = x, y
    s.r = 0
    s.maxR = EXPLOSION_MAX_RADIUS
    s.growth = EXPLOSION_GROWTH
    s.__dead = false  -- we’ll use this to purge finished explosions

    -- position & draw order
    s:moveTo(x, y)
    s:setZIndex(EXPLOSION_Z)

    local img = gfx.image.new(1, 1)
    s:setImage(img)
    s:setCollideRect(0, 0, 1, 1)

    function s:update()
        self.r += self.growth
        if self.r >= self.maxR then
            self.__dead = true
            self:remove()
            return
        end

        local d = math.max(1, math.ceil(self.r * 2))
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
    end

    s:add()
    table.insert(explosions, s)  -- <-- track it
    return s
end


-- ===== Targets =====
local function markTarget(x, y)
    table.insert(targets, { x = x, y = y })
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
    currentReticleX = originX + math.cos(rad) * reticleDistance
    currentReticleY = originY + math.sin(rad) * reticleDistance
end

-- ===== Put all primitive drawing in one function we can call from background
local function drawWorld()
    gfx.clear()

    -- enemy missiles (trail + body)
    for _, e in ipairs(enemies) do
        if #e.trail > 1 then
            for j = 2, #e.trail do
                local a, b = e.trail[j-1], e.trail[j]
                gfx.drawLine(a.x, a.y, b.x, b.y)
            end
        end
        gfx.fillCircleAtPoint(e.x, e.y, ENEMY_MISSILE_SIZE)
        gfx.drawLine(e.x, e.y, e.x + (e.vx * 2), e.y + (e.vy * 2))
    end


    -- guide & live crosshair
    local originX, originY = screenW/2, screenH
    gfx.drawLine(originX, originY, currentReticleX, currentReticleY)
    local liveCross = 5
    gfx.drawLine(currentReticleX - liveCross, currentReticleY, currentReticleX + liveCross, currentReticleY)
    gfx.drawLine(currentReticleX, currentReticleY - liveCross, currentReticleX, currentReticleY + liveCross)

    -- targets
    for _, t in ipairs(targets) do
        gfx.drawLine(t.x - TARGET_CROSS, t.y, t.x + TARGET_CROSS, t.y)
        gfx.drawLine(t.x, t.y - TARGET_CROSS, t.x, t.y + TARGET_CROSS)
    end

    -- missiles (trail + body)
    for _, m in ipairs(missiles) do
        if #m.trail > 1 then
            for j = 2, #m.trail do
                local a, b = m.trail[j-1], m.trail[j]
                gfx.drawLine(a.x, a.y, b.x, b.y)
            end
        end
        gfx.fillCircleAtPoint(m.x, m.y, MISSILE_SIZE)
        gfx.drawLine(m.x, m.y, m.x + (m.vx * 2), m.y + (m.vy * 2))
    end
end

-- ==== Register a background drawing callback so sprites won’t wipe your primitives
gfx.sprite.setBackgroundDrawingCallback(function(x, y, w, h)
    -- Redraw your entire primitive scene. (Simple & safe; can optimize later.)
    drawWorld()
end)


-- ===== Main Loop =====
function playdate.update()
    -- input/state
    moveReticle()

    -- fire / EMP
    if playdate.buttonJustPressed(playdate.kButtonLeft) then
        markTarget(currentReticleX, currentReticleY)
        launchMissile(currentReticleX, currentReticleY)
    end
    if playdate.buttonJustPressed(playdate.kButtonRight) then
        targets = {}
        -- (leave missiles flying; add missiles = {} here if EMP should cancel them)
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        launchEnemyMissile(math.random(0, screenW), math.random(40, screenW-40))
    end

    updateMissiles()
    updateEnemies()
    pruneExplosions()



    -- draw primitives now (so you see them even before the first explosion sprite ever spawns)
    drawWorld()

    -- draw sprites (explosions)
    gfx.sprite.update()

    randomSpawnEnemyMissile()
end
