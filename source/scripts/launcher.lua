import "scripts/game"
import "scripts/tunables"
import "scripts/util"
import "scripts/audio"

-- Launcher state (centered bottom)
Launcher = {
  x = Tunables.SCREEN_W/2,
  y = Tunables.LAUNCHER_Y,
  angle = 0,             -- -90..+90 degrees
  lastCrank = playdate.getCrankPosition(),
  recoil = 0,            -- visual
}

function Launcher.updateLauncherFromCrank()
  local pos = playdate.getCrankPosition()-- 0..360
  local delta = playdate.getCrankChange() or 0  -- signed
  if math.abs(delta) > 0.75 then
    -- Map crank 0..360 to -90..+90 by subtracting 180 and clamping
    local mapped = pos - 180
    mapped = Util.clamp(mapped, Launcher.LAUNCHER_MIN_ANGLE, Launcher.LAUNCHER_MAX_ANGLE)
    -- smooth a bit
    Launcher.angle = mapped
    Audio.playTick(delta) -- click per motion
  end
  Launcher.lastCrank = pos
end

function Launcher.fireMissile()
  if Game.ammo <= 0 then return end
  Game.ammo = Game.ammo - 1
  Launcher.recoil = 4
  Audio.playLaunch()

  -- convert angle to unit vector
  local rad = math.rad(Launcher.angle - 90) -- rotate so 0 deg aims up
  local dirx, diry = math.cos(rad), math.sin(rad)
  table.insert(Game.playerMissiles, {
    x = Launcher.x,
    y = Launcher.y,
    dx = dirx * Tunables.PLAYER_MISSILE_SPEED,
    dy = diry * Tunables.PLAYER_MISSILE_SPEED,
    alive = true
  })
end

-- EMP clears all active threats
function Launcher.triggerEMP()
  if Game.usedEMP >= Game.empMax or Game.empCooldown > 0 then return end
  Game.usedEMP = Game.usedEMP + 1
  Game.empCooldown = Tunables.EMP_COOLDOWN_FRAMES
  -- apply slight penalty to efficiency multiplier
  Game.efficiencyMult = math.max(0, Game.efficiencyMult - Tunables.EMP_CLEAR_PENALTY)
  -- clear threats
  for _,e in ipairs(Game.enemies) do e.alive = false end
  -- dramatic explosions along the 180° arc
  Game.addExplosion(Launcher.x, Launcher.y-40, false)
  Game.addExplosion(Launcher.x-120, Launcher.y-30, false)
  Game.addExplosion(Launcher.x+120, Launcher.y-30, false)
  Audio.playEMP()
  Util.addShake(4)
end
