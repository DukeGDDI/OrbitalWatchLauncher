import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "scripts/util"
import "scripts/draw"
import "scripts/game"
import "scripts/launcher"
import "scripts/tunables"

function playdate.update()
  -- initSoundFx()
  if Game.paused then return end
  playdate.graphics.clear(playdate.graphics.kColorWhite)

  Util.updateShake()
  playdate.graphics.setDrawOffset(Util.shake.x, Util.shake.y)

  if Game.over then
    Draw.drawGameOver()
    playdate.timer.updateTimers()
    return
  end

  Launcher.updateLauncherFromCrank()

  -- input
  if playdate.buttonJustPressed(playdate.kButtonA) then
    Launcher.fireMissile()
  end
  if playdate.buttonJustPressed(playdate.kButtonB) then
    Launcher.triggerEMP()
  end
  if Game.empCooldown > 0 then Game.empCooldown = Game.empCooldown - 1 end

  -- updates
  Game.updateMissiles()
  Game.updateEnemies()
  Game.updateExplosions()
  Game.handleCollisions()
  Game.removeDead(Game.playerMissiles, "alive")
  Game.removeDead(Game.enemies, "alive")
  Game.removeDead(Game.explosions) -- t-based

  Game.updateWaveProgress()

  -- draw
  Draw.drawGround()
  Draw.drawCities()
  Draw.drawLauncher()
  Draw.drawMissiles()
  Draw.drawExplosions()
  Draw.drawHUD()

  playdate.timer.updateTimers()
end

-- =============================================================
-- INIT
-- =============================================================
math.randomseed(playdate.getSecondsSinceEpoch())
playdate.display.setRefreshRate(50)

-- optional menu
local menu = playdate.getSystemMenu()
menu:addMenuItem("reset game", function()
  Game.cities = {}
  Game.score = 0
  Game.resetWave(1)
end)

Game.resetWave(Tunables.START_WAVE)
