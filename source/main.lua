-- main.lua — O.W.L. (Orbital Watch Launcher)
-- Playdate SDK Lua implementation based on the provided GDD
-- Author: Rodney Aiglstorfer (design), Implementation assistant
-- SDK: https://sdk.play.date/ (Lua API)
-- Notes:
--  * Playdate has no haptics; "haptics" in the GDD are emulated with brief screen shake + audio stingers.
--  * 1‑bit visuals; everything draws with gfx primitives.
--  * This is a single‑file prototype: plug into a new Playdate project as source/main.lua.
--  * Assets are not required; all SFX are synthesized with the SDK.
--  * Tweak the TUNABLES section to adjust balance/difficulty.


local pd <const> = playdate
local gfx <const> = pd.graphics
local snd <const> = pd.sound

-- =============================================================
-- TUNABLES
-- =============================================================
local SCREEN_W, SCREEN_H = 400, 240

local START_WAVE             = 1
local CITY_COUNT_MIN         = 2
local CITY_COUNT_MAX         = 6
local CITY_MAX_HP            = 3      -- "3 blocks" per GDD
local ENEMIES_PER_WAVE_BASE  = 12
local ENEMIES_PER_WAVE_GROW  = 6
local ENEMY_SPEED_MIN        = 0.6    -- pixels/frame baseline
local ENEMY_SPEED_MAX        = 1.8
local ENEMY_SPEED_WAVE_ADD   = 0.15   -- per wave
local ENEMY_SPAWN_INTERVAL   = 22     -- frames between spawns (decreases per wave)
local ENEMY_SPAWN_WAVE_ACCEL = 1

local PLAYER_MISSILE_SPEED   = 3.0
local PLAYER_START_AMMO      = 20
local PLAYER_AMMO_PER_WAVE   = 4      -- incremental ammo per wave
local EXPLOSION_RADIUS       = 24
local EXPLOSION_RADIUS_GROW  = 2      -- per wave
local EXPLOSION_DURATION     = 22     -- frames
local CHAIN_BONUS            = 50

local EMP_MAX_PER_WAVE_MIN   = 1
local EMP_MAX_PER_WAVE_MAX   = 3
local EMP_CLEAR_PENALTY      = 0.05   -- reduces efficiency multiplier
local EMP_COOLDOWN_FRAMES    = 20

local UNUSED_AMMO_MULT_BASE  = 1.0    -- multiplier floor
local UNUSED_AMMO_MULT_STEP  = 0.02   -- per unused missile

local SCORE_PER_KILL         = 100
local SCORE_PER_CITY_HIT_PEN = 200

local LAUNCHER_Y             = SCREEN_H - 18
local HORIZON_Y              = SCREEN_H - 10
local CRANK_ARC_DEG          = 180    -- left to right horizon
local LAUNCHER_MIN_ANGLE     = -90
local LAUNCHER_MAX_ANGLE     = 90

-- Screen shake params (emulated haptics)
local SHAKE_DECAY = 0.85
local SHAKE_MAX   = 4

-- =============================================================
-- UTIL
-- =============================================================
local function clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end
local function lerp(a,b,t) return a + (b-a)*t end
local function length(x,y) return math.sqrt(x*x + y*y) end
local function randf(a,b) return a + math.random()*(b-a) end

-- Simple screen shake
local shake = {x=0,y=0,power=0}
local function addShake(p) shake.power = math.min(SHAKE_MAX, shake.power + (p or 1)) end
local function updateShake()
  shake.power = shake.power * SHAKE_DECAY
  if shake.power < 0.05 then shake.power = 0 end
  if shake.power > 0 then
    shake.x = randf(-shake.power, shake.power)
    shake.y = randf(-shake.power, shake.power)
  else
    shake.x, shake.y = 0, 0
  end
end

-- =============================================================
-- AUDIO (clicks, explosions, EMP hum) — lightweight synth
-- =============================================================
local sfx = {
  tickL = snd.synth.new(snd.kWaveSine),
  tickR = snd.synth.new(snd.kWaveSine),
  launch = snd.synth.new(snd.kWaveSquare),
  boom = snd.synth.new(snd.kWaveNoise),
  emp = snd.synth.new(snd.kWaveNoise),
  hit = snd.synth.new(snd.kWaveTriangle)
}

sfx.tickL:playNote(523, 0) -- prewarm
sfx.tickR:playNote(523, 0)
sfx.launch:playNote(440, 0)
sfx.boom:setVolume(0.7)
sfx.emp:setVolume(0.5)

local function playTick(dir)
  local f = (dir < 0) and 320 or 380
  local syn = (dir < 0) and sfx.tickL or sfx.tickR
  syn:playNote(f, 0.04)
end

local function playLaunch()
  sfx.launch:playNote(720, 0.06)
end

local function playBoom()
  sfx.boom:playNote(120, 0.12)
end

local function playEMP()
  sfx.emp:playNote(60, 0.25)
end

local function playHit()
  sfx.hit:playNote(220, 0.08)
end

-- =============================================================
-- DATA STRUCTS
-- =============================================================
local Game = {
  wave = START_WAVE,
  score = 0,
  enemiesRemaining = 0,
  enemies = {},
  playerMissiles = {},
  explosions = {},
  cities = {},
  ammo = 0,
  ammoMax = 0,
  usedEMP = 0,
  empMax = 1,
  empCooldown = 0,
  efficiencyMult = UNUSED_AMMO_MULT_BASE,
  spawnTimer = 0,
  paused = false,
  over = false
}

local function resetWave(wave)
  Game.wave = wave
  Game.score = Game.score -- keep cumulative
  Game.enemies = {}
  Game.playerMissiles = {}
  Game.explosions = {}
  Game.usedEMP = 0
  Game.empCooldown = 0
  Game.empMax = clamp(EMP_MAX_PER_WAVE_MIN + math.floor((wave-1)/2), EMP_MAX_PER_WAVE_MIN, EMP_MAX_PER_WAVE_MAX)
  Game.ammoMax = PLAYER_START_AMMO + (wave-1)*PLAYER_AMMO_PER_WAVE
  Game.ammo = Game.ammoMax
  Game.efficiencyMult = UNUSED_AMMO_MULT_BASE
  Game.enemiesRemaining = ENEMIES_PER_WAVE_BASE + (wave-1)*ENEMIES_PER_WAVE_GROW
  Game.spawnTimer = 0

  -- Cities (2–6), persistent across waves until all destroyed? The GDD implies
  -- "protect cities; game over when all destroyed before wave ends". We'll initialize once at boot, and preserve state across waves.
  if #Game.cities == 0 then
    local count = math.random(CITY_COUNT_MIN, CITY_COUNT_MAX)
    local pad = 20
    local width = (SCREEN_W - pad*2)
    for i=1,count do
      local x = lerp(pad, SCREEN_W-pad, (i-0.5)/count)
      Game.cities[i] = {x=x, y=HORIZON_Y, hp=CITY_MAX_HP, dead=false}
    end
  end

  Game.over = false
end

-- Launcher state (centered bottom)
local Launcher = {
  x = SCREEN_W/2,
  y = LAUNCHER_Y,
  angle = 0,             -- -90..+90 degrees
  lastCrank = pd.getCrankPosition(),
  recoil = 0,            -- visual
}

local function updateLauncherFromCrank()
  local pos = pd.getCrankPosition() -- 0..360
  local delta = pd.getCrankChange() -- signed
  if math.abs(delta) > 0.75 then
    -- Map crank 0..360 to -90..+90 by subtracting 180 and clamping
    local mapped = pos - 180
    mapped = clamp(mapped, LAUNCHER_MIN_ANGLE, LAUNCHER_MAX_ANGLE)
    -- smooth a bit
    Launcher.angle = mapped
    playTick(delta) -- click per motion
  end
  Launcher.lastCrank = pos
end

local function fireMissile()
  if Game.ammo <= 0 then return end
  Game.ammo = Game.ammo - 1
  Launcher.recoil = 4
  playLaunch()

  -- convert angle to unit vector
  local rad = math.rad(Launcher.angle - 90) -- rotate so 0 deg aims up
  local dirx, diry = math.cos(rad), math.sin(rad)
  table.insert(Game.playerMissiles, {
    x = Launcher.x,
    y = Launcher.y,
    dx = dirx * PLAYER_MISSILE_SPEED,
    dy = diry * PLAYER_MISSILE_SPEED,
    alive = true
  })
end

-- Enemy missile spawner
local function spawnEnemy()
  if Game.enemiesRemaining <= 0 then return end
  -- spawn from top w/ random drift toward random ground target
  local sx = randf(8, SCREEN_W-8)
  local sy = -8
  -- choose target: either a city center (more likely) or empty ground
  local targetX, targetY = nil, HORIZON_Y
  local pickCity = (#Game.cities>0) and (math.random() < 0.8)
  if pickCity then
    local tries = 0
    repeat
      local ci = math.random(1, #Game.cities)
      targetX = Game.cities[ci].x + randf(-8, 8)
      tries = tries + 1
    until targetX and tries < 5
  end
  if not targetX then
    targetX = randf(16, SCREEN_W-16)
  end
  local vx = targetX - sx
  local vy = targetY - sy
  local len = math.max(1, length(vx, vy))
  local baseSpeed = randf(ENEMY_SPEED_MIN, ENEMY_SPEED_MAX) + (Game.wave-1)*ENEMY_SPEED_WAVE_ADD
  local dx = (vx/len) * baseSpeed
  local dy = (vy/len) * baseSpeed

  table.insert(Game.enemies, {
    x=sx, y=sy, dx=dx, dy=dy,
    targetX=targetX, targetY=targetY,
    alive=true
  })
  Game.enemiesRemaining = Game.enemiesRemaining - 1
end

-- Explosion helper
local function addExplosion(x,y,isChain)
  table.insert(Game.explosions, {
    x=x, y=y, r=0, t=EXPLOSION_DURATION,
    maxr = EXPLOSION_RADIUS + (Game.wave-1)*EXPLOSION_RADIUS_GROW,
    chain=isChain or false
  })
  addShake(2)
  playBoom()
end

-- EMP clears all active threats
local function triggerEMP()
  if Game.usedEMP >= Game.empMax or Game.empCooldown > 0 then return end
  Game.usedEMP = Game.usedEMP + 1
  Game.empCooldown = EMP_COOLDOWN_FRAMES
  -- apply slight penalty to efficiency multiplier
  Game.efficiencyMult = math.max(0, Game.efficiencyMult - EMP_CLEAR_PENALTY)
  -- clear threats
  for _,e in ipairs(Game.enemies) do e.alive = false end
  -- dramatic explosions along the 180° arc
  addExplosion(Launcher.x, Launcher.y-40, false)
  addExplosion(Launcher.x-120, Launcher.y-30, false)
  addExplosion(Launcher.x+120, Launcher.y-30, false)
  playEMP()
  addShake(4)
end

-- =============================================================
-- COLLISIONS & CITY DAMAGE
-- =============================================================
local function handleCollisions()
  -- Player missile: intersect enemy missile -> explode at contact
  for _,m in ipairs(Game.playerMissiles) do
    if m.alive then
      for _,e in ipairs(Game.enemies) do
        if e.alive then
          local dx = e.x - m.x
          local dy = e.y - m.y
          if dx*dx + dy*dy <= 8*8 then
            -- detonate missile
            m.alive = false
            e.alive = false
            addExplosion(m.x, m.y, false)
            Game.score = Game.score + math.floor(SCORE_PER_KILL * Game.efficiencyMult)
          end
        end
      end
    end
  end

  -- Explosions chain-kill enemies
  for _,ex in ipairs(Game.explosions) do
    if ex.t > 0 then
      local r2 = ex.r * ex.r
      for _,e in ipairs(Game.enemies) do
        if e.alive then
          local dx = e.x - ex.x
          local dy = e.y - ex.y
          if dx*dx + dy*dy <= r2 then
            e.alive = false
            addExplosion(e.x, e.y, true)
            Game.score = Game.score + math.floor((SCORE_PER_KILL + CHAIN_BONUS) * Game.efficiencyMult)
          end
        end
      end
    end
  end
end

local function cityAt(x)
  local bestIdx, bestDist = nil, 9999
  for i,c in ipairs(Game.cities) do
    if not c.dead then
      local d = math.abs(c.x - x)
      if d < bestDist then bestDist, bestIdx = d, i end
    end
  end
  return bestIdx, bestDist
end

local function applyCityImpact(e)
  -- Determine nearest city; if none (all destroyed) or enemy lands on an already-destroyed "block",
  -- no penalty is applied (per GDD "hits on already destroyed section don’t reduce score").
  local idx = cityAt(e.x)
  if not idx then return false end
  local c = Game.cities[idx]
  if c.dead then return false end

  -- Reduce hp; if outer "block" already gone, subsequent hits to that same spot don't count penalty.
  -- Simplify: decrement hp until zero; each decrement penalizes score; when 0 -> dead.
  c.hp = c.hp - 1
  addShake(3); playHit()
  if c.hp <= 0 then
    c.dead = true
  end
  -- scoring penalty only once per successful city damage event
  Game.score = Game.score - SCORE_PER_CITY_HIT_PEN
  return true
end

-- =============================================================
-- UPDATE
-- =============================================================
local function updateMissiles()
  for _,m in ipairs(Game.playerMissiles) do
    if m.alive then
      m.x = m.x + m.dx
      m.y = m.y + m.dy
      if m.x < -10 or m.x > SCREEN_W+10 or m.y < -10 or m.y > SCREEN_H+10 then
        m.alive = false
      end
    end
  end
end

local function updateEnemies()
  for _,e in ipairs(Game.enemies) do
    if e.alive then
      e.x = e.x + e.dx
      e.y = e.y + e.dy
      -- ground impact?
      if e.y >= HORIZON_Y then
        e.alive = false
        -- city damage handling; only penalize if it actually hits a surviving city block
        applyCityImpact(e)
        addExplosion(e.x, HORIZON_Y-4, false)
      end
    end
  end
end

local function updateExplosions()
  for _,ex in ipairs(Game.explosions) do
    if ex.t > 0 then
      ex.t = ex.t - 1
      local life = 1 - (ex.t / EXPLOSION_DURATION)
      ex.r = ex.maxr * life
    end
  end
end

local function removeDead(list, field)
  local i=1
  while i <= #list do
    local alive = (field and list[i][field]) or (list[i].t and list[i].t>0)
    if not alive then table.remove(list, i) else i=i+1 end
  end
end

local function allCitiesGone()
  for _,c in ipairs(Game.cities) do
    if not c.dead then return false end
  end
  return true
end

local function updateWaveProgress()
  -- Spawn pacing
  Game.spawnTimer = Game.spawnTimer - 1
  if Game.spawnTimer <= 0 and Game.enemiesRemaining > 0 then
    spawnEnemy()
    local interval = math.max(6, ENEMY_SPAWN_INTERVAL - (Game.wave-1)*ENEMY_SPAWN_WAVE_ACCEL)
    Game.spawnTimer = interval
  end

  -- Next wave or game over
  local enemiesAlive = (#Game.enemies > 0)
  if Game.enemiesRemaining == 0 and not enemiesAlive and #Game.explosions == 0 then
    -- award unused ammo multiplier bonus for next waves as persistent efficiency
    local unused = Game.ammo
    Game.efficiencyMult = UNUSED_AMMO_MULT_BASE + (unused * UNUSED_AMMO_MULT_STEP)
    resetWave(Game.wave + 1)
  end

  if allCitiesGone() then
    Game.over = true
  end
end

-- =============================================================
-- DRAW
-- =============================================================
local function drawGround()
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(0, HORIZON_Y, SCREEN_W, HORIZON_Y)
end

local function drawCities()
  for _,c in ipairs(Game.cities) do
    local h = c.hp * 6 -- 3 blocks, 6px each
    if c.dead then
      gfx.setDitherPattern(0.25, gfx.image.kDitherTypeBayer8x8)
      gfx.fillRect(c.x-10, HORIZON_Y-2, 20, 2)
      gfx.setDitherPattern(1.0, gfx.image.kDitherTypeBayer8x8)
    else
      gfx.drawRect(c.x-10, HORIZON_Y-2-h, 20, h+2)
      for i=1,c.hp do
        gfx.drawLine(c.x-10, HORIZON_Y-2-(i*6), c.x+10, HORIZON_Y-2-(i*6))
      end
    end
  end
end

local function drawLauncher()
  -- base
  gfx.fillCircleAtPoint(Launcher.x, Launcher.y, 3)

  -- barrel
  local rad = math.rad(Launcher.angle - 90)
  local bx, by = math.cos(rad), math.sin(rad)
  local L = 18 + Launcher.recoil
  gfx.drawLine(Launcher.x, Launcher.y, Launcher.x + bx*L, Launcher.y + by*L)

  -- subtle recoil decay
  Launcher.recoil = Launcher.recoil * 0.85
end

local function drawMissiles()
  for _,m in ipairs(Game.playerMissiles) do
    if m.alive then
      gfx.fillCircleAtPoint(m.x, m.y, 1)
    end
  end
  for _,e in ipairs(Game.enemies) do
    if e.alive then
      gfx.drawRect(e.x-1, e.y-1, 2, 2)
    end
  end
end

local function drawExplosions()
  for _,ex in ipairs(Game.explosions) do
    if ex.t > 0 then
      gfx.drawCircleAtPoint(ex.x, ex.y, math.max(1, ex.r))
      -- inner flicker edge
      gfx.setDitherPattern(0.5 + 0.5*math.sin(ex.r*0.2), gfx.image.kDitherTypeBayer8x8)
      gfx.drawCircleAtPoint(ex.x, ex.y, math.max(0, ex.r-3))
      gfx.setDitherPattern(1.0, gfx.image.kDitherTypeBayer8x8)
    end
  end
end

local function drawHUD()
  -- top row: wave, score, enemies remaining
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
  gfx.drawText(string.format("WAVE %d", Game.wave), 8, 6)
  gfx.drawTextAligned(string.format("SCORE %d", Game.score), SCREEN_W/2, 6, kTextAlignment.center)
  gfx.drawTextAligned(string.format("INCOMING %d", Game.enemiesRemaining + (#Game.enemies)), SCREEN_W-8, 6, kTextAlignment.right)

  -- ammo icons (two rows)
  local cols = 20
  local iconW = 8
  local pad = 2
  for i=1,Game.ammoMax do
    local row = (i-1) // cols
    local col = (i-1) % cols
    local x = 6 + col*(iconW+pad)
    local y = SCREEN_H - 28 + row*8
    if i <= Game.ammo then
      gfx.fillRect(x, y, iconW, 4)
    else
      gfx.drawRect(x, y, iconW, 4)
    end
  end

  -- EMP indicator (bottom right)
  local cx, cy = SCREEN_W - 20, SCREEN_H - 20
  gfx.drawCircleAtPoint(cx, cy, 10)
  gfx.drawCircleAtPoint(cx, cy, 6)
  gfx.drawTextAligned(tostring(Game.empMax - Game.usedEMP), cx, cy-4, kTextAlignment.center)

  -- efficiency multiplier indicator
  gfx.drawText(string.format("x%.2f", Game.efficiencyMult), SCREEN_W - 64, SCREEN_H - 34)
end

local function drawGameOver()
  gfx.fillRect(0,0,SCREEN_W,SCREEN_H)
  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  gfx.drawTextAligned("GAME OVER", SCREEN_W/2, SCREEN_H/2 - 12, kTextAlignment.center)
  gfx.drawTextAligned(string.format("FINAL SCORE: %d", Game.score), SCREEN_W/2, SCREEN_H/2 + 4, kTextAlignment.center)
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- =============================================================
-- PLAYDATE HOOKS
-- =============================================================
function pd.update()
  if Game.paused then return end
  gfx.clear(gfx.kColorWhite)

  updateShake()
  gfx.setDrawOffset(shake.x, shake.y)

  if Game.over then
    drawGameOver()
    pd.timer.updateTimers()
    return
  end

  updateLauncherFromCrank()

  -- input
  if pd.buttonJustPressed(pd.kButtonA) then
    fireMissile()
  end
  if pd.buttonJustPressed(pd.kButtonB) then
    triggerEMP()
  end
  if Game.empCooldown > 0 then Game.empCooldown = Game.empCooldown - 1 end

  -- updates
  updateMissiles()
  updateEnemies()
  updateExplosions()
  handleCollisions()
  removeDead(Game.playerMissiles, "alive")
  removeDead(Game.enemies, "alive")
  removeDead(Game.explosions) -- t-based

  updateWaveProgress()

  -- draw
  drawGround()
  drawCities()
  drawLauncher()
  drawMissiles()
  drawExplosions()
  drawHUD()

  pd.timer.updateTimers()
end

-- =============================================================
-- INIT
-- =============================================================
math.randomseed(pd.getSecondsSinceEpoch())
pd.display.setRefreshRate(50)

-- optional menu
local menu = pd.getSystemMenu()
menu:addMenuItem("reset game", function()
  Game.cities = {}
  Game.score = 0
  resetWave(1)
end)

resetWave(START_WAVE)
