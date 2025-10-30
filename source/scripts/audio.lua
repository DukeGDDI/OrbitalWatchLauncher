Audio = {}

-- =============================================================
-- Audio (clicks, explosions, EMP hum) — lightweight synth
-- =============================================================

Audio.tickL = playdate.sound.synth.new(playdate.sound.kWaveSine);
Audio.tickR = playdate.sound.synth.new(playdate.sound.kWaveSine);
Audio.launch = playdate.sound.synth.new(playdate.sound.kWaveSquare);
Audio.boom = playdate.sound.synth.new(playdate.sound.kWaveNoise);
Audio.emp = playdate.sound.synth.new(playdate.sound.kWaveNoise);
Audio.hit = playdate.sound.synth.new(playdate.sound.kWaveTriangle);

Audio.tickL:playNote(523, 0) -- prewarm
Audio.tickR:playNote(523, 0)
Audio.launch:playNote(440, 0)
Audio.boom:setVolume(0.7)
Audio.emp:setVolume(0.5)
Audio.hit:setVolume(0.6)


function Audio.playTick(dir)
  if Audio.tickL and Audio.tickR == nil then return end
  local f = (dir < 0) and 320 or 380
  local syn = (dir < 0) and Audio.tickL or Audio.tickR
  if syn then
    syn:playNote(f, 0.04)
  end
end

function Audio.playLaunch()
    if Audio.launch == nil then return end
    Audio.launch:playNote(720, 0.06)
end

function Audio.playBoom()
    if Audio.boom == nil then return end
    Audio.boom:playNote(120, 0.12)
end

function Audio.playEMP()
    if Audio.emp == nil then return end
    Audio.emp:playNote(60, 0.25)
end

function Audio.playHit()
    if Audio.hit == nil then return end
    Audio.hit:playNote(220, 0.08)
end
