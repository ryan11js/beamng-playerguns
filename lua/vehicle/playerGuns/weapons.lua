-- Shared weapon definitions and stat application for PlayerGuns mounts.

local M = {}

M.list = {
  {name = "Pistol",   meshName = "unicycle_pistol",  hasMuzzleSmoke = false, fireDelaySec = 0.18,     bulletVelocity = 1.6, bulletMass = 6,  magazineSize = 12,  reloadTimeSec = 1.2, spreadDeg = 1.2, isExplosive = false, explosionRadius = 0.50, maxBreaksPerHit = 3,   blastForce = 0,      fireSoundPitch = 2.2, fireSoundVolume = 0.7},
  {name = "Uzi",      meshName = "unicycle_uzi",     hasMuzzleSmoke = true,  fireDelaySec = 1/952*60, bulletVelocity = 1.7, bulletMass = 7,  magazineSize = 32,  reloadTimeSec = 1.5, spreadDeg = 5.5, isExplosive = false, explosionRadius = 0.55, maxBreaksPerHit = 3,   blastForce = 0,      fireSoundPitch = 2.5, fireSoundVolume = 0.8},
  {name = "Thompson", meshName = "unicycle_tom",     hasMuzzleSmoke = true,  fireDelaySec = 1/600*60, bulletVelocity = 2.3, bulletMass = 9,  magazineSize = 50,  reloadTimeSec = 2.6, spreadDeg = 3.5, isExplosive = false, explosionRadius = 0.60, maxBreaksPerHit = 4,   blastForce = 0,      fireSoundPitch = 1.8, fireSoundVolume = 1.0},
  {name = "AKM",      meshName = "unicycle_akm",     hasMuzzleSmoke = true,  fireDelaySec = 1/420*60, bulletVelocity = 3.3, bulletMass = 14, magazineSize = 30,  reloadTimeSec = 2.7, spreadDeg = 2.3, isExplosive = false, explosionRadius = 0.70, maxBreaksPerHit = 6,   blastForce = 0,      fireSoundPitch = 1.5, fireSoundVolume = 1.1},
  {name = "Sniper",   meshName = "unicycle_awp",     hasMuzzleSmoke = true,  fireDelaySec = 1.4,      bulletVelocity = 5.4, bulletMass = 80, magazineSize = 5,   reloadTimeSec = 3.0, spreadDeg = 0.0, isExplosive = false, explosionRadius = 1.50, maxBreaksPerHit = 40,  blastForce = 20000,  fireSoundPitch = 0.9, fireSoundVolume = 1.4},
  {name = "Minigun",  meshName = "unicycle_minigun", hasMuzzleSmoke = true,  fireDelaySec = 0.04,     bulletVelocity = 2.0, bulletMass = 8,  magazineSize = 250, reloadTimeSec = 4.5, spreadDeg = 4.3, isExplosive = false, explosionRadius = 0.55, maxBreaksPerHit = 3,   blastForce = 0,      fireSoundPitch = 2.7, fireSoundVolume = 0.95},
  {name = "Bazooka",  meshName = "unicycle_bazooka", hasMuzzleSmoke = true,  fireDelaySec = 1.0,      bulletVelocity = 2.9, bulletMass = 95, magazineSize = 1,   reloadTimeSec = 3.0, spreadDeg = 0.0, isExplosive = true,  explosionRadius = 5.0,  maxBreaksPerHit = 170, blastForce = 130000, fireSoundPitch = 0.7, fireSoundVolume = 1.6},
}

-- Explicit muzzle speed (m/s) per weapon. With the physics-step launch
-- (force = dv * mass * 2000 applied at 2000 Hz) these are REAL, exact exit
-- speeds — the old ~100 m/s ceiling was an artifact of applying launch forces
-- from the frame-rate hook without the *2000 step conversion.
local MUZZLE_SPEEDS = {
  Pistol = 180,
  Uzi = 200,
  Thompson = 190,
  AKM = 250,
  Sniper = 350,
  Minigun = 220,
  Bazooka = 35,  -- slow visible rocket lob
}
for _, w in ipairs(M.list) do
  w.muzzleSpeed = MUZZLE_SPEEDS[w.name] or 180
end

function M.newMagUsed()
  return {0, 0, 0, 0, 0, 0, 0}
end

function M.applyStats(state, selectedIdx)
  local w = M.list[selectedIdx]
  state.fireDelaySec = w.fireDelaySec
  state.bulletVelocity = w.bulletVelocity
  state.muzzleSpeed = w.muzzleSpeed
  state.bulletMass = w.bulletMass
  state.magazineSize = w.magazineSize
  state.reloadTimeSec = w.reloadTimeSec
  state.spreadDeg = w.spreadDeg or 0
  state.isExplosive = w.isExplosive or false
  state.explosionRadius = w.explosionRadius or 0.35
  state.maxBreaksPerHit = w.maxBreaksPerHit or 2
  state.fireSoundPitch = w.fireSoundPitch or 2
  state.fireSoundVolume = w.fireSoundVolume or 1
  state.blastForce = w.blastForce or 0
  state.hasMuzzleSmoke = w.hasMuzzleSmoke ~= false

  electrics.values.pg_show_pistol  = (selectedIdx == 1) and 1 or 0
  electrics.values.pg_show_uzi     = (selectedIdx == 2) and 1 or 0
  electrics.values.pg_show_tom     = (selectedIdx == 3) and 1 or 0
  electrics.values.pg_show_akm     = (selectedIdx == 4) and 1 or 0
  electrics.values.pg_show_sniper  = (selectedIdx == 5) and 1 or 0
  electrics.values.pg_show_minigun = (selectedIdx == 6) and 1 or 0
  electrics.values.pg_show_bazooka = (selectedIdx == 7) and 1 or 0
end

return M
