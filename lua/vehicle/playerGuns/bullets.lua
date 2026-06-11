-- Bullet launch, impact particles, and recycling for PlayerGuns.
--
-- LAUNCH MODEL (telemetry-calibrated for current BeamNG):
--
--   obj:applyForceVector(node, (targetVel - nodeVel) * mass)
--   ...executed ONCE per shot from the controller's physics-step `update`
--   hook, open-loop (velocity captured at queue time, never read back).
--
-- Hard-won rules, each one paid for with a broken test session:
--  * Call context matters. From updateGFX the delivered velocity change is an
--    FPS-dependent fraction (the historical "soggy bullets / aim degrades
--    over the session" bugs, inherited from pw2). From the physics hook it is
--    a clean impulse: dv = F/m exactly (measured; the legacy stefan750
--    "*2000" factor overshoots by exactly 2000x here).
--  * Open-loop only. getNodeVelocityVector is FRAME-cached — any read-back
--    correction loop at physics rate sees stale values and diverges
--    exponentially (telemetry once logged bullets at 1e35 m/s).
--
-- Frame-rate code (launchNextBullet, updateBulletImpacts) only QUEUES physics
-- jobs; updatePhysics() runs each exactly once: set position, set exact
-- velocity, done. Parking cancels velocity the same way, so recycled nodes
-- are truly at rest.

local damage = require("playerGuns/damage")
local telem = require("playerGuns/telem")

local M = {}

local abs = math.abs

local _diagLaunchCount = 0

-- Park strays/spent bullets when they get this far from the vehicle (m) or
-- fall out of the world vertically.
local STRAY_RANGE = 800
local STRAY_Z = 500
-- Hard flight-time ceiling. The EFFECTIVE per-shot cap is computed at launch
-- from the firing weapon's rate so the 100-node pool can never starve:
--   cap = min(MAX_FLIGHT_SEC, poolSize * fireDelay * 0.75)
-- Minigun (25/s): 3.0s. Uzi: 4.7s. Slow weapons: full 7s.
local MAX_FLIGHT_SEC = 7
-- Tracer particles only for the visually relevant part of the flight.
local TRACER_SEC = 1.5
-- Impact detection blind window after launch (covers the launch step plus one
-- render frame).
local LAUNCH_GRACE_SEC = 0.05

local function dirWorldToLocal(dir)
  local yVec = obj:getDirectionVector():normalized()
  local zVec = obj:getDirectionVectorUp():normalized()
  local xVec = zVec:cross(yVec):normalized()
  return vec3(dir:dot(xVec), dir:dot(yVec), dir:dot(zVec)):normalized()
end

local function computeSpawnLocal(state, dir)
  local muzzleLocal = vec3(obj:getNodePosition(state.bulletOriginNodeId))
  local offset = state.bulletSpawnOffset or 0
  if offset > 0 then
    local off = dirWorldToLocal(dir) * offset
    -- Never spawn BELOW the muzzle: with steep downward aim the offset used to
    -- place the bullet inside the engine bay where it clipped terrain through
    -- the car. The bullet still FLIES downward from the muzzle.
    if off.z < 0 then off.z = 0 end
    muzzleLocal = muzzleLocal + off
  end
  return muzzleLocal
end

-- World-space position of the muzzle node (vehicle origin + local muzzle rotated into world).
function M.muzzleWorldPos(state)
  if not state.bulletOriginNodeId then return vec3(obj:getPosition()) end
  local ml = vec3(obj:getNodePosition(state.bulletOriginNodeId))
  local fwd = obj:getDirectionVector():normalized()
  local up = obj:getDirectionVectorUp():normalized()
  local right = up:cross(fwd):normalized()
  local vp = vec3(obj:getPosition())
  return vp + right * ml.x + fwd * ml.y + up * ml.z
end

-- ---------------------------------------------------------------------------
-- Physics-step job queue (run from the controller's 2000 Hz update hook)
-- ---------------------------------------------------------------------------

local physJobs = {}
local physJobCount = 0

local function queueJob(node, job)
  -- A node can only have one live job; a new one supersedes it.
  if node.pgJob then node.pgJob.dead = true end
  node.pgJob = job
  job.node = node
  physJobCount = physJobCount + 1
  physJobs[physJobCount] = job
end

-- Exact velocity change. MEASURED semantics of applyForceVector when called
-- from this controller's physics-step hook: direct impulse, dv = F/m.
-- (v0.8.1 shipped the legacy stefan750 "* 2000" step-conversion factor here
-- and telemetry clocked every bullet at exactly muzzleSpeed*2000 — 500 km/s.
-- Whatever engine era that factor belonged to, on current BeamNG in this
-- call context the impulse form is the correct one.)
local function applyVelocityDelta(cid, dvx, dvy, dvz, mass)
  obj:applyForceVector(cid, vec3(dvx * mass, dvy * mass, dvz * mass))
end

-- Each job runs EXACTLY ONCE, open-loop, using the velocity captured at queue
-- time (job.vx/vy/vz). NEVER use a read-back correction loop here:
-- getNodeVelocityVector is FRAME-cached, so a closed loop at physics rate
-- re-applies the full correction ~33x per frame and the velocity diverges
-- exponentially (telemetry once recorded bullets at 1e35 m/s). This single
-- open-loop set is exactly what UniversalWeapons/Bell407 do — they track
-- commanded velocity in their own table (projectileVel) instead of reading
-- back, and it demonstrably works.
function M.updatePhysics(state, dt)
  if physJobCount == 0 then return end
  for i = 1, physJobCount do
    local job = physJobs[i]
    physJobs[i] = nil
    if not job.dead then
      local node = job.node
      if job.kind == 'launch' then
        obj:setNodeMass(node.cid, job.mass)
        obj:setNodePosition(node.cid, job.spawn)
        applyVelocityDelta(node.cid, job.tx - job.vx, job.ty - job.vy, job.tz - job.vz, job.mass)
      else -- 'park': cancel motion, stow the node under the vehicle
        applyVelocityDelta(node.cid, -job.vx, -job.vy, -job.vz, 0.01)
        if job.rest then
          obj:setNodePosition(node.cid, vec3(job.rest.x, job.rest.y, job.rest.z))
        end
      end
      node.pgJob = nil
    else
      job.node.pgJob = (job.node.pgJob == job) and nil or job.node.pgJob
    end
  end
  physJobCount = 0
end

-- ---------------------------------------------------------------------------
-- Parking / pool management
-- ---------------------------------------------------------------------------

-- Retire a bullet: flag it out of flight and queue a physics job that stops it
-- dead and teleports it back under the vehicle. skipCancel: used by the
-- force-retire path where the node is relaunched in the same call — the launch
-- job sets the exact new velocity anyway, so only the flags/teleport matter.
local function parkBullet(node, skipCancel)
  node.pgInFlight = false
  node.pgFlightTime = nil
  node.pgLaunchGrace = nil
  node.horizontalVelocity = nil
  node.newHorizontalVelocity = nil
  if skipCancel then
    if node.pgJob then node.pgJob.dead = true node.pgJob = nil end
    return
  end
  obj:setNodeMass(node.cid, 0.01)
  local vel = vec3(obj:getNodeVelocityVector(node.cid))
  -- Sanity clamp: never build a cancel force out of a runaway/NaN velocity.
  if not (vel:length() < 4000) then vel = vec3(0, 0, 0) end
  queueJob(node, {
    kind = 'park',
    vx = vel.x, vy = vel.y, vz = vel.z,
    rest = node.pgRestPos,
  })
end

-- bulletID -> node lookup, built once (v.data.nodes refs are stable).
local function nodeIndex(state)
  if not state._nodeByBulletId then
    local m = {}
    for _, node in pairs(v.data.nodes) do
      local bid = tonumber(node.pg_bulletID)
      if bid then m[bid] = node end
    end
    state._nodeByBulletId = m
  end
  return state._nodeByBulletId
end

-- Pick the next bullet node, parked nodes only. If the pool is starved the
-- oldest airborne bullet is force-retired and used (its stale velocity is
-- irrelevant — the launch job sets the exact new velocity).
local function pickBulletNode(state)
  local idxMap = nodeIndex(state)
  local total = state.totalBullets
  for i = 0, total - 1 do
    local id = ((state.currentBulletIdx - 1 + i) % total) + 1
    local n = idxMap[id]
    if n and not n.pgInFlight then
      return n, id, false
    end
  end
  local id = ((state.currentBulletIdx - 1) % total) + 1
  local n = idxMap[id]
  if n then parkBullet(n, true) end
  return n, id, true
end

-- Per-shot detail flows into the telemetry recorder; keep a few log lines.
local LAUNCH_LOG_LIMIT = 5

function M.launchNextBullet(state, weapons, selectedWeaponIdx, aimDirection, diagCamCallbackCount)
  if state.currentBulletIdx > state.totalBullets then
    state.currentBulletIdx = 1
  end

  local dir = aimDirection
  -- Convergence at fire-time: re-aim from the actual muzzle toward the world
  -- target so shots cross the crosshair.
  if state.aimTargetWorld and (electrics.values.pg_aim_converge_enabled or 0) > 0.5 then
    local d = state.aimTargetWorld - M.muzzleWorldPos(state)
    if d:length() > 0.01 then dir = d:normalized() end
  end

  if dir:length() < 0.01 then
    log('W', 'playerGuns.launchNextBullet', 'BAIL: aimDirection length is zero — camera callback never delivered. cam-callback-count=' .. tostring(diagCamCallbackCount) ..
        ' mount=' .. tostring(state.mountContext))
    telem.onBail(state, 'zero aim direction (camCallbacks=' .. tostring(diagCamCallbackCount) .. ')')
    return
  end

  -- Recoil/spread gate: only when enabled via the Controls UI toggle.
  if state.recoilEnabled and state.spreadDeg and state.spreadDeg > 0 then
    local up = vec3(0, 0, 1)
    local right = dir:cross(up)
    if right:length() < 0.001 then right = vec3(1, 0, 0) end
    right = right:normalized()
    local upPerp = right:cross(dir):normalized()
    local rad = state.spreadDeg * math.pi / 180
    local theta = math.random() * 2 * math.pi
    local r = math.sqrt(math.random()) * math.tan(rad)
    local jitter = right * (r * math.cos(theta)) + upPerp * (r * math.sin(theta))
    dir = (dir + jitter):normalized()
  end

  _diagLaunchCount = _diagLaunchCount + 1
  local spawnLocal = computeSpawnLocal(state, dir)

  local node, bulletId, hotReuse = pickBulletNode(state)

  if node then
    local nodeVel = vec3(obj:getNodeVelocityVector(node.cid))
    -- Sanity clamp: never build a cancel force out of a runaway/NaN velocity.
    if not (nodeVel:length() < 4000) then nodeVel = vec3(0, 0, 0) end
    local vehVel = vec3(obj:getVelocity())
    local targetVel = dir * state.muzzleSpeed + vehVel

    node.exploded = false
    node.pgInFlight = true
    node.pgFlightTime = 0
    -- Flight cap scaled to fire rate so this weapon can never starve the pool.
    node.pgMaxFlight = math.min(MAX_FLIGHT_SEC, state.totalBullets * math.max(state.fireDelaySec, 0.02) * 0.75)
    node.pgLaunchGrace = LAUNCH_GRACE_SEC
    node.horizontalVelocity = nil
    node.newHorizontalVelocity = nil

    queueJob(node, {
      kind = 'launch',
      mass = state.bulletMass,
      spawn = spawnLocal,
      tx = targetVel.x, ty = targetVel.y, tz = targetVel.z,
      vx = nodeVel.x, vy = nodeVel.y, vz = nodeVel.z,
    })

    telem.onShot(state, node.cid, state.bulletsFired + 1, selectedWeaponIdx, dir,
      hotReuse, nodeVel:length())

    if _diagLaunchCount <= LAUNCH_LOG_LIMIT then
      local vehPos = vec3(obj:getPosition())
      local wname = (weapons and weapons.list and weapons.list[selectedWeaponIdx] and weapons.list[selectedWeaponIdx].name) or '?'
      log('I', 'playerGuns.launch', string.format(
        '#%d weapon=%s mount=%s muzzleSpeed=%.0f spawnWorld=(%.2f,%.2f,%.2f) aim=(%.3f,%.3f,%.3f) staleVel=%.1f vehVel=%.1f hotReuse=%s',
        _diagLaunchCount, wname, tostring(state.mountContext), state.muzzleSpeed,
        vehPos.x + spawnLocal.x, vehPos.y + spawnLocal.y, vehPos.z + spawnLocal.z,
        dir.x, dir.y, dir.z, nodeVel:length(), vehVel:length(), tostring(hotReuse)))
    end
  else
    log('W', 'playerGuns.launch', 'No bullet node for id=' .. tostring(bulletId) .. ' mount=' .. tostring(state.mountContext))
  end

  state.currentBulletIdx = bulletId

  if state.fireParticleNodeInner and state.fireParticleNodeOuter then
    obj:addParticleByNodesRelative(state.fireParticleNodeInner, state.fireParticleNodeOuter, 15, 61, 0, 1)
    obj:addParticleByNodesRelative(state.fireParticleNodeInner, state.fireParticleNodeOuter, 10, 62, 0, 1)
    obj:addParticleByNodesRelative(state.fireParticleNodeInner, state.fireParticleNodeOuter, 20, 63, 0, 1)
    obj:addParticleByNodesRelative(state.fireParticleNodeInner, state.fireParticleNodeOuter,  8, 64, 0, 1)
    obj:addParticleByNodesRelative(state.fireParticleNodeInner, state.fireParticleNodeOuter, 12, 65, 0, 1)
    if state.hasMuzzleSmoke and state.fireDelaySec >= 0.15 then
      obj:addParticleByNodesRelative(state.fireParticleNodeInner, state.fireParticleNodeOuter, 10, 6, 0, 1)
    end
  end

  if state.gunSoundNodeId then
    obj:playSFXOnce("CrashTestSound", state.gunSoundNodeId, state.fireSoundVolume, state.fireSoundPitch)
  end

  state.currentBulletIdx = state.currentBulletIdx + 1
  state.bulletsFired = state.bulletsFired + 1
end

function M.updateBulletImpacts(state, weapons, selectedWeaponIdx, dt)
  dt = dt or 0.016
  for _, node in pairs(v.data.nodes) do
    if node.pg_bulletID and node.pgInFlight then
      node.pgFlightTime = (node.pgFlightTime or 0) + dt
      if node.pgFlightTime > (node.pgMaxFlight or MAX_FLIGHT_SEC) then
        parkBullet(node)
        goto continue
      end

      if node.pgLaunchGrace and node.pgLaunchGrace > 0 then
        node.pgLaunchGrace = node.pgLaunchGrace - dt
      end

      if not node.exploded and node.pgFlightTime < TRACER_SEC then
        obj:addParticleByNodesRelative(node.cid, node.cid, 1200000, 67, 0, 10)
      end

      local velocity = vec3(obj:getNodeVelocityVector(node.cid))
      if node.newHorizontalVelocity == nil then
        node.newHorizontalVelocity = abs(velocity.x) + abs(velocity.y)
      else
        node.horizontalVelocity = node.newHorizontalVelocity
        node.newHorizontalVelocity = abs(velocity.x) + abs(velocity.y)
        local inGrace = node.pgLaunchGrace and node.pgLaunchGrace > 0
        if not node.exploded and not inGrace and (node.horizontalVelocity - node.newHorizontalVelocity) > 0.01 then
          if state.isExplosive then
            obj:addParticleByNodesRelative(node.cid, node.cid, 30, 29, 0.4, 12)
            obj:addParticleByNodesRelative(node.cid, node.cid, 25,  9, 0.01, 8)
            obj:addParticleByNodesRelative(node.cid, node.cid, 20, 52, 0.01, 6)
            obj:addParticleByNodesRelative(node.cid, node.cid, 40, 25, 0.0,  4)
          else
            obj:addParticleByNodesRelative(node.cid, node.cid, 12, 1,  0.0002, 1)
            obj:addParticleByNodesRelative(node.cid, node.cid, 15, 61, 0.0002, 1)
            obj:addParticleByNodesRelative(node.cid, node.cid, 10, 62, 0.0002, 1)
            obj:addParticleByNodesRelative(node.cid, node.cid, 20, 63, 0.0002, 1)
            obj:addParticleByNodesRelative(node.cid, node.cid,  8, 64, 0.0002, 1)
            obj:addParticleByNodesRelative(node.cid, node.cid, 12, 65, 0.0002, 1)
            obj:addParticleByNodesRelative(node.cid, node.cid, 10,  6, 0.0002, 1)
          end
          node.exploded = true
          -- Order matters: telemetry + damage capture the impact position
          -- BEFORE the node is parked back under the vehicle.
          telem.onImpact(state, node.cid)
          damage.notifyImpact(state, node.cid, selectedWeaponIdx, weapons)
          parkBullet(node)
        end
      end
    end
    ::continue::
  end
end

function M.recycleStrayBullets(state)
  for _, node in pairs(v.data.nodes) do
    if node.pg_bulletID and node.pgInFlight then
      local p = vec3(obj:getNodePosition(node.cid))
      if abs(p.z) > STRAY_Z or (p.x * p.x + p.y * p.y) > (STRAY_RANGE * STRAY_RANGE) then
        parkBullet(node)
      end
    end
  end
end

function M.resetPhysicsJobs()
  for i = 1, physJobCount do
    local job = physJobs[i]
    if job and job.node then job.node.pgJob = nil end
    physJobs[i] = nil
  end
  physJobCount = 0
end

return M
