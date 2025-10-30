import "scripts/util"
import "scripts/tunables"
import "scripts/audio"
-- =============================================================
-- GAME STATE   
-- =============================================================
Game = {
  wave = Tunables.START_WAVE,
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
  efficiencyMult = Tunables.UNUSED_AMMO_MULT_BASE,
  spawnTimer = 0,
  paused = false,
  over = false
}

function Game.resetWave(wave)
  Game.wave = wave
  Game.score = Game.score -- keep cumulative
  Game.enemies = {}
  Game.playerMissiles = {}
  Game.explosions = {}
  Game.usedEMP = 0
  Game.empCooldown = 0
  Game.empMax = Util.clamp(Tunables.EMP_MAX_PER_WAVE_MIN + math.floor((wave-1)/2), Tunables.EMP_MAX_PER_WAVE_MIN, Tunables.EMP_MAX_PER_WAVE_MAX)
  Game.ammoMax = Tunables.PLAYER_START_AMMO + (wave-1)*Tunables.PLAYER_AMMO_PER_WAVE
  Game.ammo = Game.ammoMax
  Game.efficiencyMult = Tunables.UNUSED_AMMO_MULT_BASE
  Game.enemiesRemaining = Tunables.ENEMIES_PER_WAVE_BASE + (wave-1)*Tunables.ENEMIES_PER_WAVE_GROW
  Game.spawnTimer = 0

  -- Cities (2–6), persistent across waves until all destroyed? The GDD implies
  -- "protect cities; game over when all destroyed before wave ends". We'll initialize once at boot, and preserve state across waves.
  if #Game.cities == 0 then
    local count = math.random(Tunables.CITY_COUNT_MIN, Tunables.CITY_COUNT_MAX)
    local pad = 20
    local width = (Tunables.SCREEN_W - pad*2)
    for i=1,count do
      local x = Util.lerp(pad, Tunables.SCREEN_W-pad, (i-0.5)/count)
      Game.cities[i] = {x=x, y=Tunables.HORIZON_Y, hp=Tunables.CITY_MAX_HP, dead=false}
    end
  end

  Game.over = false
end

function Game.updateMissiles()
  for _,m in ipairs(Game.playerMissiles) do
    if m.alive then
      m.x = m.x + m.dx
      m.y = m.y + m.dy
      if m.x < -10 or m.x > Tunables.SCREEN_W+10 or m.y < -10 or m.y > Tunables.SCREEN_H+10 then
        m.alive = false
      end
    end
  end
end

function Game.updateEnemies()
  for _,e in ipairs(Game.enemies) do
    if e.alive then
      e.x = e.x + e.dx
      e.y = e.y + e.dy
      -- ground impact?
      if e.y >= Tunables.HORIZON_Y then
        e.alive = false
        -- city damage handling; only penalize if it actually hits a surviving city block
        Game.applyCityImpact(e)
        Game.addExplosion(e.x, Tunables.HORIZON_Y-4, false)
      end
    end
  end
end

function Game.updateExplosions()
  for _,ex in ipairs(Game.explosions) do
    if ex.t > 0 then
      ex.t = ex.t - 1
      local life = 1 - (ex.t / Tunables.EXPLOSION_DURATION)
      ex.r = ex.maxr * life
    end
  end
end

function Game.removeDead(list, field)
  local i=1
  while i <= #list do
    local alive = (field and list[i][field]) or (list[i].t and list[i].t>0)
    if not alive then table.remove(list, i) else i=i+1 end
  end
end

function Game.allCitiesGone()
  for _,c in ipairs(Game.cities) do
    if not c.dead then return false end
  end
  return true
end

function Game.updateWaveProgress()
  -- Spawn pacing
  Game.spawnTimer = Game.spawnTimer - 1
  if Game.spawnTimer <= 0 and Game.enemiesRemaining > 0 then
    Game.spawnEnemy()
    local interval = math.max(6, Tunables.ENEMY_SPAWN_INTERVAL - (Game.wave-1)*Tunables.ENEMY_SPAWN_WAVE_ACCEL)
    Game.spawnTimer = interval
  end

  -- Next wave or game over
  local enemiesAlive = (#Game.enemies > 0)
  if Game.enemiesRemaining == 0 and not enemiesAlive and #Game.explosions == 0 then
    -- award unused ammo multiplier bonus for next waves as persistent efficiency
    local unused = Game.ammo
    Game.efficiencyMult = Tunables.UNUSED_AMMO_MULT_BASE + (unused * Tunables.UNUSED_AMMO_MULT_STEP)
    Game.resetWave(Game.wave + 1)
  end

  if Game.allCitiesGone() then
    Game.over = true
  end
end

-- Enemy missile spawner
function Game.spawnEnemy()
  if Game.enemiesRemaining <= 0 then return end
  -- spawn from top w/ random drift toward random ground target
  local sx = Util.randf(8, Tunables.SCREEN_W-8)
  local sy = -8
  -- choose target: either a city center (more likely) or empty ground
  local targetX, targetY = nil, Tunables.HORIZON_Y
  local pickCity = (#Game.cities>0) and (math.random() < 0.8)
  if pickCity then
    local tries = 0
    repeat
      local ci = math.random(1, #Game.cities)
      targetX = Game.cities[ci].x + Util.randf(-8, 8)
      tries = tries + 1
    until targetX and tries < 5
  end
  if not targetX then
    targetX = Util.randf(16, Tunables.SCREEN_W-16)
  end
  local vx = targetX - sx
  local vy = targetY - sy
  local len = math.max(1, Util.length(vx, vy))
  local baseSpeed = Util.randf(Tunables.ENEMY_SPEED_MIN, Tunables.ENEMY_SPEED_MAX) + (Game.wave-1)*Tunables.ENEMY_SPEED_WAVE_ADD
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
function Game.addExplosion(x,y,isChain)
  table.insert(Game.explosions, {
    x=x, y=y, r=0, t=Tunables.EXPLOSION_DURATION,
    maxr = Tunables.EXPLOSION_RADIUS + (Game.wave-1)*Tunables.EXPLOSION_RADIUS_GROW,
    chain=isChain or false
  })
  Util.addShake(2)
  Audio.playBoom()
end

-- =============================================================
-- COLLISIONS & CITY DAMAGE
-- =============================================================
function Game.handleCollisions()
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
            Game.addExplosion(m.x, m.y, false)
            Game.score = Game.score + math.floor(Tunables.SCORE_PER_KILL * Game.efficiencyMult)
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
            Game.addExplosion(e.x, e.y, true)
            Game.score = Game.score + math.floor((Tunables.SCORE_PER_KILL + Tunables.CHAIN_BONUS) * Game.efficiencyMult)
          end
        end
      end
    end
  end
end

function Game.cityAt(x)
  local bestIdx, bestDist = nil, 9999
  for i,c in ipairs(Game.cities) do
    if not c.dead then
      local d = math.abs(c.x - x)
      if d < bestDist then bestDist, bestIdx = d, i end
    end
  end
  return bestIdx, bestDist
end

function Game.applyCityImpact(e)
  -- Determine nearest city; if none (all destroyed) or enemy lands on an already-destroyed "block",
  -- no penalty is applied (per GDD "hits on already destroyed section don’t reduce score").
  local idx = Game.cityAt(e.x)
  if not idx then return false end
  local c = Game.cities[idx]
  if c.dead then return false end

  -- Reduce hp; if outer "block" already gone, subsequent hits to that same spot don't count penalty.
  -- Simplify: decrement hp until zero; each decrement penalizes score; when 0 -> dead.
  c.hp = c.hp - 1
  Util.addShake(3); Audio.playHit()
  if c.hp <= 0 then
    c.dead = true
  end
  -- scoring penalty only once per successful city damage event
  Game.score = Game.score - Tunables.SCORE_PER_CITY_HIT_PEN
  return true
end

-- =============================================================