Tunables = {}
-- =============================================================
-- TUNABLES
-- =============================================================
Tunables.SCREEN_W, Tunables.SCREEN_H = 400, 240

Tunables.START_WAVE             = 1
Tunables.CITY_COUNT_MIN         = 2
Tunables.CITY_COUNT_MAX         = 6
Tunables.CITY_MAX_HP            = 3      -- "3 blocks" per GDD
Tunables.ENEMIES_PER_WAVE_BASE  = 12
Tunables.ENEMIES_PER_WAVE_GROW  = 6
Tunables.ENEMY_SPEED_MIN        = 0.6    -- pixels/frame baseline
Tunables.ENEMY_SPEED_MAX        = 1.8
Tunables.ENEMY_SPEED_WAVE_ADD   = 0.15   -- per wave
Tunables.ENEMY_SPAWN_INTERVAL   = 22     -- frames between spawns (decreases per wave)
Tunables.ENEMY_SPAWN_WAVE_ACCEL = 1

Tunables.PLAYER_MISSILE_SPEED   = 3.0
Tunables.PLAYER_START_AMMO      = 20
Tunables.PLAYER_AMMO_PER_WAVE   = 4      -- incremental ammo per wave
Tunables.EXPLOSION_RADIUS       = 24
Tunables.EXPLOSION_RADIUS_GROW  = 2      -- per wave
Tunables.EXPLOSION_DURATION     = 22     -- frames
Tunables.CHAIN_BONUS            = 50

Tunables.EMP_MAX_PER_WAVE_MIN   = 1
Tunables.EMP_MAX_PER_WAVE_MAX   = 3
Tunables.EMP_CLEAR_PENALTY      = 0.05   -- reduces efficiency multiplier
Tunables.EMP_COOLDOWN_FRAMES    = 20

Tunables.UNUSED_AMMO_MULT_BASE  = 1.0    -- multiplier floor
Tunables.UNUSED_AMMO_MULT_STEP  = 0.02   -- per unused missile

Tunables.SCORE_PER_KILL         = 100
Tunables.SCORE_PER_CITY_HIT_PEN = 200

Tunables.LAUNCHER_Y             = Tunables.SCREEN_H - 18
Tunables.HORIZON_Y              = Tunables.SCREEN_H - 10
Tunables.CRANK_ARC_DEG          = 180    -- left to right horizon
Tunables.LAUNCHER_MIN_ANGLE     = -90
Tunables.LAUNCHER_MAX_ANGLE     = 90

-- =============================================================