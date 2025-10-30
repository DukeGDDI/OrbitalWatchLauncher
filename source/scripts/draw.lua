import "CoreLibs/graphics"

import "scripts/game"
import "scripts/launcher"
import "scripts/tunables"

local pd  <const> = playdate
local gfx <const> = pd.graphics

-- =============================================================
-- DRAW
-- =============================================================
Draw = {}

function Draw.drawGround()
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(0, Tunables.HORIZON_Y, Tunables.SCREEN_W, Tunables.HORIZON_Y)
end

function Draw.drawCities()
  for _,c in ipairs(Game.cities) do
    local h = c.hp * 6 -- 3 blocks, 6px each
    if c.dead then
      gfx.setDitherPattern(0.25, gfx.image.kDitherTypeBayer8x8)
      gfx.fillRect(c.x-10, Tunables.HORIZON_Y-2, 20, 2)
      gfx.setDitherPattern(1.0, gfx.image.kDitherTypeBayer8x8)
    else
      gfx.drawRect(c.x-10, Tunables.HORIZON_Y-2-h, 20, h+2)
      for i=1,c.hp do
        gfx.drawLine(c.x-10, Tunables.HORIZON_Y-2-(i*6), c.x+10, Tunables.HORIZON_Y-2-(i*6))
      end
    end
  end
end

function Draw.drawLauncher()
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

function Draw.drawMissiles()
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

function Draw.drawExplosions()
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

function Draw.drawHUD()
  local alignment = gfx.kTextAlignment
  -- top row: wave, score, enemies remaining
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
  gfx.drawText(string.format("WAVE %d", Game.wave), 8, 6)
  gfx.drawTextAligned(string.format("SCORE %d", Game.score), Tunables.SCREEN_W/2, 6)
  gfx.drawTextAligned(string.format("INCOMING %d", Game.enemiesRemaining + (#Game.enemies)), Tunables.SCREEN_W-8, 6)

  -- ammo icons (two rows)
  local cols = 20
  local iconW = 8
  local pad = 2
  for i=1,Game.ammoMax do
    local row = (i-1) // cols
    local col = (i-1) % cols
    local x = 6 + col*(iconW+pad)
    local y = Tunables.SCREEN_H - 28 + row*8
    if i <= Game.ammo then
      gfx.fillRect(x, y, iconW, 4)
    else
      gfx.drawRect(x, y, iconW, 4)
    end
  end

  -- EMP indicator (bottom right)
  local cx, cy = Tunables.SCREEN_W - 20, Tunables.SCREEN_H - 20
  gfx.drawCircleAtPoint(cx, cy, 10)
  gfx.drawCircleAtPoint(cx, cy, 6)
  gfx.drawTextAligned(tostring(Game.empMax - Game.usedEMP), cx, cy-4) --, gfx.kTextAlignment.center)

  -- efficiency multiplier indicator
  gfx.drawText(string.format("x%.2f", Game.efficiencyMult), Tunables.SCREEN_W - 64, Tunables.SCREEN_H - 34)
end

function Draw.drawGameOver()
  gfx.fillRect(0,0,Tunables.SCREEN_W,Tunables.SCREEN_H)
  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  gfx.drawTextAligned("GAME OVER", Tunables.SCREEN_W/2, Tunables.SCREEN_H/2 - 12) --, gfx.kTextAlignment.center)
  gfx.drawTextAligned(string.format("FINAL SCORE: %d", Game.score), Tunables.SCREEN_W/2, Tunables.SCREEN_H/2 + 4) --, gfx.kTextAlignment.center)
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

-- =============================================================