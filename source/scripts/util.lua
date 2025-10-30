-- =============================================================
-- UTIL
-- =============================================================

Util = {}

Util.SHAKE_DECAY = 0.85
Util.SHAKE_MAX   = 4

function Util.clamp(x, a, b) 
  -- if any of a,b is nil, treat as unbounded
  if a == nil and b == nil then return x end
  if a == nil then return math.min(x, b) end
  if b == nil then return math.max(x, a) end
  if x < a then 
    return a 
  elseif x > b then 
    return b 
  else 
    return x 
  end
end

function Util.lerp(a,b,t) return a + (b-a)*t end
function Util.length(x,y) return math.sqrt(x*x + y*y) end
function Util.randf(a,b) return a + math.random()*(b-a) end

-- Simple screen shake
Util.shake = {x=0,y=0,power=0}
function Util.addShake(p) Util.shake.power = math.min(Util.SHAKE_MAX, Util.shake.power + (p or 1)) end
function Util.updateShake()
  Util.shake.power = Util.shake.power * Util.SHAKE_DECAY
  if Util.shake.power < 0.05 then Util.shake.power = 0 end
  if Util.shake.power > 0 then
    Util.shake.x = Util.randf(-Util.shake.power, Util.shake.power)
    Util.shake.y = Util.randf(-Util.shake.power, Util.shake.power)
  else
    Util.shake.x, Util.shake.y = 0, 0
  end
end

-- =============================================================