-- Shared weapon definitions and stat application for PlayerGuns mounts.
--
-- Adding a weapon is one row in M.list. Optional fields:
--   meshName / showElectric  nil = no model shown for this weapon (e.g. thrown
--                            explosives). showElectric drives the jbeam prop.
--   fireSoundFile            looked up in M.SFX_DIR at runtime; weapons whose
--                            file is missing fall back to the stock sample.
-- muzzleSpeed is the real exit speed in m/s (the physics-step launch delivers
-- it exactly). Lobbed weapons just use a low muzzleSpeed; gravity does the arc.

local M = {}

M.SFX_DIR = '/vehicles/common/playerGuns/sfx/'

M.list = {
  {name = "Pistol",   meshName = "unicycle_pistol",  showElectric = "pg_show_pistol",  fireSoundFile = "pistol.ogg",   hasMuzzleSmoke = false, fireDelaySec = 0.18,     muzzleSpeed = 180, bulletMass = 6,  magazineSize = 12,  reloadTimeSec = 1.2, spreadDeg = 1.2, isExplosive = false, explosionRadius = 0.50, maxBreaksPerHit = 3,   blastForce = 0,      fireSoundPitch = 2.2, fireSoundVolume = 0.7},
  {name = "Uzi",      meshName = "unicycle_uzi",     showElectric = "pg_show_uzi",     fireSoundFile = "uzi.ogg",      hasMuzzleSmoke = true,  fireDelaySec = 1/952*60, muzzleSpeed = 200, bulletMass = 7,  magazineSize = 32,  reloadTimeSec = 1.5, spreadDeg = 5.5, isExplosive = false, explosionRadius = 0.55, maxBreaksPerHit = 3,   blastForce = 0,      fireSoundPitch = 2.5, fireSoundVolume = 0.8},
  {name = "Thompson", meshName = "unicycle_tom",     showElectric = "pg_show_tom",     fireSoundFile = "thompson.ogg", hasMuzzleSmoke = true,  fireDelaySec = 1/600*60, muzzleSpeed = 190, bulletMass = 9,  magazineSize = 50,  reloadTimeSec = 2.6, spreadDeg = 3.5, isExplosive = false, explosionRadius = 0.60, maxBreaksPerHit = 4,   blastForce = 0,      fireSoundPitch = 1.8, fireSoundVolume = 1.0},
  {name = "AKM",      meshName = "unicycle_akm",     showElectric = "pg_show_akm",     fireSoundFile = "akm.ogg",      hasMuzzleSmoke = true,  fireDelaySec = 1/420*60, muzzleSpeed = 250, bulletMass = 14, magazineSize = 30,  reloadTimeSec = 2.7, spreadDeg = 2.3, isExplosive = false, explosionRadius = 0.70, maxBreaksPerHit = 6,   blastForce = 0,      fireSoundPitch = 1.5, fireSoundVolume = 1.1},
  {name = "Sniper",   meshName = "unicycle_awp",     showElectric = "pg_show_sniper",  fireSoundFile = "sniper.ogg",   hasMuzzleSmoke = true,  fireDelaySec = 1.4,      muzzleSpeed = 350, bulletMass = 80, magazineSize = 5,   reloadTimeSec = 3.0, spreadDeg = 0.0, isExplosive = false, explosionRadius = 1.50, maxBreaksPerHit = 40,  blastForce = 20000,  fireSoundPitch = 0.9, fireSoundVolume = 1.4},
  {name = "Minigun",  meshName = "unicycle_minigun", showElectric = "pg_show_minigun", fireSoundFile = "minigun.ogg",  hasMuzzleSmoke = true,  fireDelaySec = 0.04,     muzzleSpeed = 220, bulletMass = 8,  magazineSize = 250, reloadTimeSec = 4.5, spreadDeg = 4.3, isExplosive = false, explosionRadius = 0.55, maxBreaksPerHit = 3,   blastForce = 0,      fireSoundPitch = 2.7, fireSoundVolume = 0.95},
  {name = "Bazooka",  meshName = "unicycle_bazooka", showElectric = "pg_show_bazooka", fireSoundFile = "bazooka.ogg",  hasMuzzleSmoke = true,  fireDelaySec = 1.0,      muzzleSpeed = 35,  bulletMass = 95, magazineSize = 1,   reloadTimeSec = 3.0, spreadDeg = 0.0, isExplosive = true,  explosionRadius = 5.0,  maxBreaksPerHit = 170, blastForce = 130000, fireSoundPitch = 0.7, fireSoundVolume = 1.6},
  -- Thrown explosive: no model, lobbed arc, detonates on impact. Future bombs
  -- follow this pattern (a row with isExplosive and a low muzzleSpeed).
  {name = "Grenade",  meshName = nil,                showElectric = nil,               fireSoundFile = "grenade.ogg",  hasMuzzleSmoke = false, fireDelaySec = 1.0,      muzzleSpeed = 22,  bulletMass = 30, magazineSize = 5,   reloadTimeSec = 2.5, spreadDeg = 0.0, isExplosive = true,  explosionRadius = 6.5,  maxBreaksPerHit = 400, blastForce = 220000, fireSoundPitch = 0.8, fireSoundVolume = 1.3},
}

function M.newMagUsed()
  local t = {}
  for i = 1, #M.list do t[i] = 0 end
  return t
end

function M.applyStats(state, selectedIdx)
  local w = M.list[selectedIdx]
  state.fireDelaySec = w.fireDelaySec
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

  for i, ww in ipairs(M.list) do
    if ww.showElectric then
      electrics.values[ww.showElectric] = (i == selectedIdx) and 1 or 0
    end
  end
end

return M
