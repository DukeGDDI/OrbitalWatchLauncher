-- gameplay.lua
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/keyboard"

local gfx <const> = playdate.graphics

-- ===== Screen =====
local SCREEN_WIDTH, SCREEN_HEIGHT = 400, 240

-- ===== Config =====
local MIN_DISTANCE         = 15
local MAX_DISTANCE         = 250

local DISTANCE_SPEED       = 2.2     -- px/frame (Up/Down)
local CRANK_ANGLE_SENS     = 1.0     -- deg reticle rotation per 1 deg crank change

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
local ENEMY_MISSILE_SPEED    = 1.5   -- px/frame (slightly slower than player)
local ENEMY_TRAIL_MAX_POINTS = 30
local ENEMY_TRAIL_STEP       = 3
local ENEMY_MISSILE_SIZE     = 2
local ENEMY_SPAWN_RATE       = 0.02

-- ===== Utils =====
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ===== Class =====
GamePlay = {}
GamePlay.__index = GamePlay

function GamePlay.new()
    local self = setmetatable({}, GamePlay)

    -- State
    self.reticleAngle = 270
    self.reticleDistance = 60
    self.currentReticleX, self.currentReticleY = 0, 0

    self.targets = {}      -- { {x=, y=} }
    self.missiles = {}     -- missiles are tables (primitives)
    self.enemies = {}      -- enemy missiles (same structure)
    self.explosions = {}   -- holds active explosion sprites we create

    -- Background callback: redraw primitives behind sprites
    gfx.sprite.setBackgroundDrawingCallback(function(x, y, w, h)
        self:drawWorld()
    end)

    return self
end

-- ===== Explosion Sprite (instance-based) =====
function GamePlay:newExplosion(x, y)
    local s = gfx.sprite.new()

    -- custom fields (closed over)
    local cx, cy = x, y
    local r = 0
    local maxR = EXPLOSION_MAX_RADIUS
    local growth = EXPLOSION_GROWTH
    local dead = false

    s:moveTo(x, y)
    s:setZIndex(EXPLOSION_Z)

    local img = gfx.image.new(1, 1)
    s:setImage(img)
    s:setCollideRect(0, 0, 1, 1)

    function s:getBlast()
        return cx, cy, r, dead
    end

    s.update = function()
        r += growth
        if r >= maxR then
            dead = true
            s:remove()
            return
        end

        local d = math.max(1, math.ceil(r * 2))
        local newImg = gfx.image.new(d, d)
        gfx.pushContext(newImg)
            gfx.drawCircleInRect(0, 0, d, d)
            local inner = math.floor(r * 0.6) * 2
            if inner > 2 then
                local inset = math.floor((d - inner) / 2)
                gfx.drawCircleInRect(inset, inset, inner, inner)
            end
        gfx.popContext()

        s:setImage(newImg)
        s:setCollideRect(0, 0, d, d)
    end

    s:add()
    table.insert(self.explosions, s)
    return s
end

function GamePlay:pruneExplosions()
    for i = #self.explosions, 1, -1 do
        if self.explosions[i].__dead then
            table.remove(self.explosions, i)
        end
    end
end

-- ===== Targets =====
function GamePlay:markTarget(x, y)
    table.insert(self.targets, { x = x, y = y })
end

-- ===== Player Missiles =====
function GamePlay:launchMissile(targetX, targetY)
    local originX, originY = SCREEN_WIDTH/2, SCREEN_HEIGHT
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
    table.insert(self.missiles, m)
end

function GamePlay:updateMissiles()
    for i = #self.missiles, 1, -1 do
        local m = self.missiles[i]

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
            for t = #self.targets, 1, -1 do
                if math.abs(self.targets[t].x - m.tx) < 2 and math.abs(self.targets[t].y - m.ty) < 2 then
                    table.remove(self.targets, t)
                    break
                end
            end

            -- Spawn explosion sprite
            self:newExplosion(m.x, m.y)

            -- Remove missile
            table.remove(self.missiles, i)
        end
    end
end

-- ===== Enemy Missiles =====
function GamePlay:launchEnemyMissile(xOrigin, xTarget)
    xOrigin = clamp(xOrigin, 0, SCREEN_WIDTH)
    xTarget = clamp(xTarget, 0, SCREEN_WIDTH)

    local originX, originY = xOrigin, 0
    local targetX, targetY = xTarget, SCREEN_HEIGHT

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
    table.insert(self.enemies, e)
end

function GamePlay:updateEnemies()
    self:pruneExplosions()

    for i = #self.enemies, 1, -1 do
        local e = self.enemies[i]

        -- advance
        e.x += e.vx
        e.y += e.vy

        -- trail
        local dx, dy = (e.x - e.lastTrailX), (e.y - e.lastTrailY)
        if (dx*dx + dy*dy) >= (ENEMY_TRAIL_STEP * ENEMY_TRAIL_STEP) then
            table.insert(e.trail, { x = e.x, y = e.y })
            e.lastTrailX, e.lastTrailY = e.x, e.y
            if #e.trail > ENEMY_TRAIL_MAX_POINTS then
                table.remove(e.trail, 1)
            end
        end

        -- explosion overlap check
        local destroyed = false
        for _, ex in ipairs(self.explosions) do
            local exx, exy, exr, exdead = ex:getBlast()
            if not exdead then
                local exdx, exdy = e.x - exx, e.y - exy
                if (exdx*exdx + exdy*exdy) <= (exr * exr) then
                    self:newExplosion(e.x, e.y)
                    table.remove(self.enemies, i)
                    destroyed = true
                    break
                end
            end
        end

        if not destroyed then
            -- arrival at ground?
            local txd, tyd = (e.tx - e.x), (e.ty - e.y)
            local dist2 = txd*txd + tyd*tyd
            if dist2 <= (e.speed * e.speed) then
                e.x, e.y = e.tx, e.ty
                self:newExplosion(e.x, e.y)  -- ground impact
                table.remove(self.enemies, i)
            end
        end
    end
end

function GamePlay:randomSpawnEnemyMissile()
    if math.random() < ENEMY_SPAWN_RATE then
        self:launchEnemyMissile(math.random(0, SCREEN_WIDTH), math.random(40, SCREEN_WIDTH-40))
    end
end

-- ===== Reticle =====
function GamePlay:moveReticle()
    -- rotation via crank
    local crankDeltaDeg = playdate.getCrankChange()
    self.reticleAngle += crankDeltaDeg * CRANK_ANGLE_SENS

    -- distance via Up/Down
    if playdate.buttonIsPressed(playdate.kButtonUp) then
        self.reticleDistance += DISTANCE_SPEED
    elseif playdate.buttonIsPressed(playdate.kButtonDown) then
        self.reticleDistance -= DISTANCE_SPEED
    end
    self.reticleDistance = clamp(self.reticleDistance, MIN_DISTANCE, MAX_DISTANCE)

    -- polar -> cartesian
    local rad = math.rad(self.reticleAngle)
    local originX, originY = SCREEN_WIDTH/2, SCREEN_HEIGHT
    self.currentReticleX = originX + math.cos(rad) * self.reticleDistance
    self.currentReticleY = originY + math.sin(rad) * self.reticleDistance
end

-- ===== Drawing (primitives; sprites draw via gfx.sprite.update) =====
function GamePlay:drawWorld()
    gfx.clear()

    -- enemy missiles (trail + body)
    for _, e in ipairs(self.enemies) do
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
    local originX, originY = SCREEN_WIDTH/2, SCREEN_HEIGHT
    gfx.drawLine(originX, originY, self.currentReticleX, self.currentReticleY)
    local liveCross = 5
    gfx.drawLine(self.currentReticleX - liveCross, self.currentReticleY, self.currentReticleX + liveCross, self.currentReticleY)
    gfx.drawLine(self.currentReticleX, self.currentReticleY - liveCross, self.currentReticleX, self.currentReticleY + liveCross)

    -- targets
    for _, t in ipairs(self.targets) do
        gfx.drawLine(t.x - TARGET_CROSS, t.y, t.x + TARGET_CROSS, t.y)
        gfx.drawLine(t.x, t.y - TARGET_CROSS, t.x, t.y + TARGET_CROSS)
    end

    -- player missiles (trail + body)
    for _, m in ipairs(self.missiles) do
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

-- ===== Main update =====
function GamePlay:update()
    -- input/state
    self:moveReticle()

    -- fire / EMP
    if playdate.buttonJustPressed(playdate.kButtonLeft) then
        self:markTarget(self.currentReticleX, self.currentReticleY)
        self:launchMissile(self.currentReticleX, self.currentReticleY)
    end
    if playdate.buttonJustPressed(playdate.kButtonRight) then
        self.targets = {}
        -- (leave missiles flying; set self.missiles = {} to cancel them too)
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        self:launchEnemyMissile(math.random(0, SCREEN_WIDTH), math.random(40, SCREEN_WIDTH-40))
    end

    self:updateMissiles()
    self:updateEnemies()
    self:pruneExplosions()

    -- draw primitives now
    self:drawWorld()

    -- draw sprites (explosions)
    gfx.sprite.update()

    self:randomSpawnEnemyMissile()
end
