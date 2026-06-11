-- PlayerGuns telemetry collector (vehicle side).
--
-- Measures what actually happened to each bullet (real velocity vs intended
-- aim, impact distance from the firing car, mount-node sag) and forwards
-- compact events to the GE-side recorder (playerGuns/telemetry.lua).
-- Only the LOCAL owner sends events; remote BeamMP replays stay silent.

local M = {}

-- Two trajectory samples per shot. The physics-step launch reaches exact
-- velocity within ~3 steps (1.5 ms), so an early sample grades launch quality
-- and a later one shows in-flight effects (gravity droop grows between them).
local SAMPLE_TIMES = { 0.05, 0.20 }
local SAG_INTERVAL = 5.0

local pendingByCid = {}   -- [nodeCid] = {n=shotNo, dir=vec3, age=0, samples=0, launchedAt=<telemTime>}
local telemTime = 0
local sagAccum = 0
local muzzleRestLocal = nil

local function send(code)
  obj:queueGameEngineLua(
    'if extensions and extensions.playerGuns_telemetry then ' .. code .. ' end')
end

-- Rest pose is captured ~1.5s AFTER init so the mount has settled on its
-- beams first (capturing at init showed a fake 0.3m baseline "sag").
local REST_CAPTURE_DELAY = 1.5

function M.init(state)
  pendingByCid = {}
  telemTime = 0
  sagAccum = 0
  muzzleRestLocal = nil
end

-- Called from bullets.launchNextBullet with the FINAL direction (after
-- convergence / spread were applied). hotReuse=true means the node was still
-- in flight when reused (staleSpd = its leftover speed in m/s).
function M.onShot(state, nodeCid, shotNo, weaponIdx, dir, hotReuse, staleSpd)
  if not state.isLocal then return end
  pendingByCid[nodeCid] = {
    n = shotNo,
    dir = vec3(dir.x, dir.y, dir.z),
    age = 0,
    samples = 0,
    launchedAt = telemTime,
  }
  send(string.format('extensions.playerGuns_telemetry.evShot(%d,%d,%d,%d,%.1f)',
    obj:getID(), shotNo, weaponIdx, hotReuse and 1 or 0, staleSpd or 0))
end

-- Called from bullets.updateBulletImpacts when a bullet detonates.
function M.onImpact(state, nodeCid)
  if not state.isLocal then return end
  local p = pendingByCid[nodeCid]
  local shotNo = p and p.n or -1
  local flight = p and (telemTime - p.launchedAt) or -1
  -- node-local position length ~= distance from the firing vehicle's origin
  local localPos = vec3(obj:getNodePosition(nodeCid))
  send(string.format('extensions.playerGuns_telemetry.evImpact(%d,%d,%.2f,%.2f)',
    obj:getID(), shotNo, localPos:length(), flight))
  pendingByCid[nodeCid] = nil
end

function M.onBail(state, reason)
  if not state.isLocal then return end
  send(string.format('extensions.playerGuns_telemetry.evBail(%d,%q)', obj:getID(), tostring(reason)))
end

function M.update(state, dt)
  if not state.isLocal then return end
  telemTime = telemTime + dt

  -- Trajectory error: compare the bullet node's actual velocity direction
  -- with the direction we intended to fire it in, at two points in the
  -- flight. The error is decomposed into a vertical part (gravity/drag droop)
  -- and a lateral part (launch residual / deflection) in world axes.
  for cid, p in pairs(pendingByCid) do
    if p.samples < #SAMPLE_TIMES then
      p.age = p.age + dt
      if p.age >= SAMPLE_TIMES[p.samples + 1] then
        p.samples = p.samples + 1
        local vel = vec3(obj:getNodeVelocityVector(cid))
        -- subtract vehicle velocity: we grade the muzzle direction, not the carry
        local rel = vel - vec3(obj:getVelocity())
        local speed = rel:length()
        if speed > 2000 then
          -- Physics blew up on this node (runaway force). Record the anomaly
          -- as its own counter instead of poisoning the speed/error averages.
          send(string.format('extensions.playerGuns_telemetry.evWild(%d,%d,%.3e)', obj:getID(), p.n, speed))
          pendingByCid[cid] = nil
        elseif speed > 1 then
          local relN = rel:normalized()
          local cosA = math.max(-1, math.min(1, relN:dot(p.dir)))
          local errDeg = math.deg(math.acos(cosA))
          local perp = relN - p.dir * cosA
          local vertComp = math.max(-1, math.min(1, perp.z))
          local vertDeg = math.deg(math.asin(vertComp))
          local perpLen2 = perp:dot(perp)
          local latDeg = math.deg(math.asin(math.min(1, math.sqrt(math.max(0, perpLen2 - vertComp * vertComp)))))
          send(string.format('extensions.playerGuns_telemetry.evTraj(%d,%d,%.2f,%.1f,%d,%.2f,%.2f)',
            obj:getID(), p.n, errDeg, speed, p.samples, vertDeg, latDeg))
        end
      end
    end
  end

  -- Mount sag: how far the muzzle node has drifted from its rest position
  -- (jbeam deformation of the gun mount = aim degradation source).
  if not muzzleRestLocal and telemTime >= REST_CAPTURE_DELAY and state.bulletOriginNodeId then
    muzzleRestLocal = vec3(obj:getNodePosition(state.bulletOriginNodeId))
  end
  sagAccum = sagAccum + dt
  if sagAccum >= SAG_INTERVAL then
    sagAccum = 0
    if muzzleRestLocal and state.bulletOriginNodeId then
      local now = vec3(obj:getNodePosition(state.bulletOriginNodeId))
      local sag = (now - muzzleRestLocal):length()
      -- Vehicle tilt from vertical (deg). If the per-shot vertical error
      -- tracks this number, the "error" is the car parked on a slope (a
      -- measurement frame artifact), not a ballistics problem.
      local up = obj:getDirectionVectorUp():normalized()
      local tiltDeg = math.deg(math.acos(math.max(-1, math.min(1, up.z))))
      send(string.format('extensions.playerGuns_telemetry.evSag(%d,%.4f,%.2f)', obj:getID(), sag, tiltDeg))
    end
  end
end

return M
