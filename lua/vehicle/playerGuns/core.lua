-- PlayerGuns core controller — shared by unicycle (walking) and roof (vehicle) mounts.
-- Camera aim via core_camera.getForward(); no turret servos or barrel recoil on host vehicle.

local weapons = require("playerGuns/weapons")
local bullets = require("playerGuns/bullets")
local damage = require("playerGuns/damage")
local telem = require("playerGuns/telem")

local M = {}

local min = math.min
local max = math.max

local state = {
  mountContext = "unicycle",
  totalBullets = 100,
  gunSoundNodeName = "driver",
  fireParticleNodeInnerName = "bc1",
  fireParticleNodeOuterName = "pg_gun_node",
  bulletOriginNodeName = "driver",
  hydroAnchorNodeName = "b2",
  bulletSpawnOffset = 0,

  selectedWeaponIdx = 1,
  magUsed = weapons.newMagUsed(),
  currentBulletIdx = 1,
  timeSinceLastShot = 0,
  reloading = false,
  reloadTimer = 0,
  bulletsFired = 0,
  aimDirection = vec3(0, 0, 0),
  aimTargetWorld = nil,

  gunSoundNodeId = nil,
  fireParticleNodeInner = nil,
  fireParticleNodeOuter = nil,
  bulletOriginNodeId = nil,

  fireDelaySec = 0,
  bulletVelocity = 0,
  muzzleSpeed = 200,
  bulletMass = 0,
  magazineSize = 0,
  reloadTimeSec = 0,
  spreadDeg = 0,
  isExplosive = false,
  explosionRadius = 0.35,
  maxBreaksPerHit = 2,
  fireSoundPitch = 2,
  fireSoundVolume = 1,
  blastForce = 0,
  hasMuzzleSmoke = true,
  -- Recoil/spread is OFF by default. Driven by electrics.values.pg_recoil_enabled
  -- which the Player Guns Controls UI app flips via the input-bridge extension.
  recoilEnabled = false,
  -- Refreshed every frame; gates telemetry sends so BeamMP remote replicas stay silent.
  isLocal = true,
}

local _diagFrameCount = 0
local _diagSecondsAccum = 0
local _diagCamCallbackCount = 0
local _diagFireAttempts = 0
local _diagReloadPresses = 0
local _diagSwitchPresses = 0
local _hudRefreshAccum = 0
local _lastVisibilityIdx = nil
M._lastSeenPulse = 0
M._lastFireValue = 0

local function isLocalOwner()
  if v and v.mpVehicleType then
    return v.mpVehicleType ~= "R"
  end
  return true
end

local function resolveNodeId(name)
  if not name then return nil end
  for _, node in pairs(v.data.nodes) do
    if node.name == name then return node.cid end
  end
  return nil
end

local function publishHud()
  local w = weapons.list[state.selectedWeaponIdx]
  local ammoLeft = max(0, w.magazineSize - state.magUsed[state.selectedWeaponIdx])
  local payload = {
    weapon = w.name,
    ammo = ammoLeft,
    mag = w.magazineSize,
    reserve = -1,
    reloading = state.reloading,
    reloadProgress = state.reloading and (1 - (state.reloadTimer / w.reloadTimeSec)) or 0,
    mountContext = state.mountContext,
  }
  if guihooks and guihooks.trigger then
    guihooks.trigger("playerGuns_hud", payload)
  end
end

local function applyMeshVisibility()
  if _lastVisibilityIdx == state.selectedWeaponIdx then return end
  _lastVisibilityIdx = state.selectedWeaponIdx
  -- Both mounts now render weapons as flexbodies (roof) / props+flexbodies (unicycle)
  -- and switch visibility via setMeshAlpha by mesh name.
  local id = obj:getID()
  local parts = {string.format("local v = be:getObjectByID(%d) if not v or not v.setMeshAlpha then return end ", id)}
  for i, w in ipairs(weapons.list) do
    if w.meshName then
      local a = (i == state.selectedWeaponIdx) and 1 or 0
      parts[#parts+1] = string.format("v:setMeshAlpha(%d, '%s', false) ", a, w.meshName)
    end
  end
  obj:queueGameEngineLua(table.concat(parts))
  log('I', 'playerGuns.visibility', 'setMeshAlpha applied mount=' .. state.mountContext .. ' weapon=' .. weapons.list[state.selectedWeaponIdx].name)
end

local function applyWeaponStats()
  weapons.applyStats(state, state.selectedWeaponIdx)
  applyMeshVisibility()
end

local function selectWeapon(idx)
  if type(idx) ~= 'number' or idx < 1 or idx > #weapons.list then return end
  state.selectedWeaponIdx = idx
  applyWeaponStats()
  if state.reloading then
    state.reloading = false
    state.reloadTimer = 0
  end
  electrics.values.pg_selected_weapon = state.selectedWeaponIdx
  publishHud()
end

local function switchWeapon(direction)
  local idx = state.selectedWeaponIdx + direction
  if idx > #weapons.list then idx = 1 end
  if idx < 1 then idx = #weapons.list end
  selectWeapon(idx)
end

local function notifyInputBridge(active)
  obj:queueGameEngineLua(
    "if extensions and extensions.playerGuns_input then extensions.playerGuns_input.setActive(" ..
    tostring(active and true or false) .. ") end"
  )
end

local function vehicleSimStable()
  if v and v.vehicleIsStable ~= nil then
    return v.vehicleIsStable
  end
  return true
end

local function queueCameraAim()
  obj:queueGameEngineLua(string.format(
    "if extensions and extensions.playerGuns_aim and extensions.playerGuns_aim.pushAimRayToVehicle then extensions.playerGuns_aim.pushAimRayToVehicle(%d) end",
    obj:getID()
  ))
end

-- Ask the GE side which sound files exist; reply lands in setSfxAvailable.
-- Runs once per init so dropping files in only needs a Ctrl+R.
local function probeSfxFiles()
  local quoted = {}
  for _, w in ipairs(weapons.list) do
    if w.fireSoundFile then quoted[#quoted + 1] = string.format('%q', w.fireSoundFile) end
  end
  quoted[#quoted + 1] = '"reload.ogg"'
  obj:queueGameEngineLua(string.format([[
    (function()
      local files = {%s}
      local found = {}
      for _, f in ipairs(files) do
        if FS:fileExists(%q .. f) then found[#found + 1] = string.format('%%q', f) end
      end
      local veh = be:getObjectByID(%d)
      if veh then
        veh:queueLuaCommand('local c = controller.getControllerSafe("playerGuns") if c and c.setSfxAvailable then c.setSfxAvailable({' .. table.concat(found, ',') .. '}) end')
      end
    end)()
  ]], table.concat(quoted, ','), weapons.SFX_DIR, obj:getID()))
end

local function playReloadSound()
  if state.sfxAvail and state.sfxAvail['reload.ogg'] then
    obj:queueGameEngineLua("Engine.Audio.playOnce('AudioGui', '" .. weapons.SFX_DIR .. "reload.ogg')")
  end
end

local function applyConfig(jbeamData)
  local cfg = jbeamData or {}
  state.mountContext = cfg.mountContext or "unicycle"
  state.totalBullets = cfg.totalBullets or 100
  state.gunSoundNodeName = cfg.gunSoundNodeName or state.gunSoundNodeName
  state.fireParticleNodeInnerName = cfg.fireParticleNodeInnerName or state.fireParticleNodeInnerName
  state.fireParticleNodeOuterName = cfg.fireParticleNodeOuterName or state.fireParticleNodeOuterName
  state.bulletOriginNodeName = cfg.bulletOriginNodeName or state.bulletOriginNodeName
  state.hydroAnchorNodeName = cfg.hydroAnchorNodeName or state.hydroAnchorNodeName
  state.bulletSpawnOffset = cfg.bulletSpawnOffset or state.bulletSpawnOffset or 0
end

function M.camForwardCallback(tx, ty, tz)
  _diagCamCallbackCount = _diagCamCallbackCount + 1
  -- (tx,ty,tz) is a WORLD-SPACE target point on the camera ray (parallax
  -- convergence). The vehicle also sees pg_ray_dir_x/y/z set by aim.lua —
  -- when convergence is DISABLED we ignore the target and aim along rayDir
  -- from the muzzle directly (predictable "bullets fly parallel to camera"
  -- behavior; no surprise downward yank when crosshair grazes foreground).
  state.aimTargetWorld = vec3(tx, ty, tz)
  local muzzle = bullets.muzzleWorldPos(state)
  local convergeEnabled = (electrics.values.pg_aim_converge_enabled or 0) > 0.5

  local dir
  if convergeEnabled then
    dir = state.aimTargetWorld - muzzle
  else
    local rx = electrics.values.pg_ray_dir_x or 0
    local ry = electrics.values.pg_ray_dir_y or 0
    local rz = electrics.values.pg_ray_dir_z or 0
    dir = vec3(rx, ry, rz)
  end
  if dir:length() > 0.001 then
    state.aimDirection = dir:normalized()
  end
  if _diagCamCallbackCount <= 3 then
    log('I', 'playerGuns.cam', string.format(
      'camForwardCallback #%d mount=%s converge=%s target=(%.1f,%.1f,%.1f) muzzle=(%.1f,%.1f,%.1f) dir=(%.3f,%.3f,%.3f)',
      _diagCamCallbackCount, state.mountContext, tostring(convergeEnabled),
      tx, ty, tz, muzzle.x, muzzle.y, muzzle.z,
      state.aimDirection.x, state.aimDirection.y, state.aimDirection.z))
  end
  -- Publish the world target for BeamMP remote replay (remote derives its own muzzle->target dir).
  electrics.values.pg_aim_x = tx
  electrics.values.pg_aim_y = ty
  electrics.values.pg_aim_z = tz
end

function M.switchWeapon(direction)
  switchWeapon(direction)
end

-- Direct selection (weapon wheel and future UI). 1-based index into weapons.list.
function M.selectWeapon(idx)
  selectWeapon(math.floor(tonumber(idx) or 0))
end

-- Sound availability, pushed back by the GE-side file probe (see probeSfxFiles).
function M.setSfxAvailable(list)
  state.sfxAvail = {}
  local n = 0
  for _, f in ipairs(list or {}) do
    state.sfxAvail[f] = true
    n = n + 1
  end
  log('I', 'playerGuns.sfx', n .. ' sound file(s) found in ' .. weapons.SFX_DIR)
end

function M.init(jbeamData)
  applyConfig(jbeamData)

  log('I', 'playerGuns.init', '=========================================')
  log('I', 'playerGuns.init', 'PlayerGuns controller init() mount=' .. state.mountContext)
  log('I', 'playerGuns.init', 'jbeamData.totalBullets = ' .. tostring(state.totalBullets))
  log('I', 'playerGuns.init', 'bulletOriginNodeName = ' .. tostring(state.bulletOriginNodeName))
  log('I', 'playerGuns.init', '=========================================')

  state.gunSoundNodeId = resolveNodeId(state.gunSoundNodeName)
  state.fireParticleNodeInner = resolveNodeId(state.fireParticleNodeInnerName)
  state.fireParticleNodeOuter = resolveNodeId(state.fireParticleNodeOuterName)
  state.bulletOriginNodeId = resolveNodeId(state.bulletOriginNodeName)

  if not state.bulletOriginNodeId and state.fireParticleNodeOuter then
    state.bulletOriginNodeId = state.fireParticleNodeOuter
  end

  log('I', 'playerGuns.mount', string.format(
    'mount=%s vehId=%d origin=%s(%s) muzzle=%s sound=%s hydroAnchor=%s meshSource=/vehicles/common/playerGuns/playerGuns_models.dae',
    state.mountContext,
    obj:getID(),
    tostring(state.bulletOriginNodeName), tostring(state.bulletOriginNodeId),
    tostring(state.fireParticleNodeOuterName), tostring(state.gunSoundNodeId),
    tostring(state.hydroAnchorNodeName)
  ))

  if not state.bulletOriginNodeId then
    log('E', 'playerGuns.mount', 'MISSING bullet origin node "' .. tostring(state.bulletOriginNodeName) .. '" — fire will BAIL')
  end

  -- One-line placement sanity check (roof OK if muzzle z > 1.0).
  if state.bulletOriginNodeId then
    local gp = vec3(obj:getNodePosition(state.bulletOriginNodeId))
    log('I', 'playerGuns.pos', string.format(
      'muzzle rest local=(%.3f, %.3f, %.3f)', gp.x, gp.y, gp.z))
  end

  for _, node in pairs(v.data.nodes) do
    if node.pg_bulletID then
      node.horizontalVelocity = nil
      node.newHorizontalVelocity = nil
      node.exploded = false
      node.pgInFlight = false
      -- Rest position (jbeam spawn pos) — spent bullets get parked back here.
      if not node.pgRestPos then
        local p = vec3(obj:getNodePosition(node.cid))
        node.pgRestPos = { x = p.x, y = p.y, z = p.z }
      end
    end
  end

  electrics.values.pg_fire = 0
  electrics.values.pg_reload = 0
  electrics.values.pg_weaponUp = 0
  electrics.values.pg_weaponDown = 0
  electrics.values.pg_gun_lift = 0
  electrics.values.pg_fire_pulse = 0
  electrics.values.pg_aim_x = 0
  electrics.values.pg_aim_y = 0
  electrics.values.pg_aim_z = 0
  electrics.values.pg_crosshair_x = 0.5
  electrics.values.pg_crosshair_y = 0.5
  electrics.values.pg_selected_weapon = 1
  electrics.values.pg_mount_context = state.mountContext
  electrics.values.pg_active = 1
  -- Recoil OFF by default. UI toggle (Player Guns Controls) writes 1/0 here.
  if electrics.values.pg_recoil_enabled == nil then
    electrics.values.pg_recoil_enabled = 0
  end
  state.recoilEnabled = (electrics.values.pg_recoil_enabled or 0) > 0.5
  -- Convergence OFF by default. When OFF the bullet flies along the camera
  -- forward rayDir from the muzzle (predictable; no surprise downward yank
  -- when crosshair grazes foreground terrain in 3rd person). When ON the
  -- bullet aims at the world point the crosshair ray hit.
  if electrics.values.pg_aim_converge_enabled == nil then
    electrics.values.pg_aim_converge_enabled = 0
  end
  electrics.values.pg_ray_dir_x = electrics.values.pg_ray_dir_x or 0
  electrics.values.pg_ray_dir_y = electrics.values.pg_ray_dir_y or 0
  electrics.values.pg_ray_dir_z = electrics.values.pg_ray_dir_z or 0

  state.selectedWeaponIdx = 1
  state._loggedUnstable = false
  state._aimAccum = 0
  _lastVisibilityIdx = nil
  applyWeaponStats()
  state.magUsed = weapons.newMagUsed()
  state.currentBulletIdx = 1
  state.timeSinceLastShot = 0
  state.reloading = false
  state.reloadTimer = 0
  state.bulletsFired = 0
  _diagReloadPresses = 0
  _diagSwitchPresses = 0
  _hudRefreshAccum = 0
  _diagCamCallbackCount = 0
  _diagFireAttempts = 0
  state.aimDirection = vec3(0, 0, 0)
  state.aimTargetWorld = nil
  M._lastSeenPulse = 0
  M._lastFireValue = 0
  damage.resetDiagnostics()
  bullets.resetPhysicsJobs()
  state.isLocal = isLocalOwner()
  state._wheelOpen = false
  state.sfxAvail = nil
  state.sfxIds = nil
  electrics.values.pg_wheel = 0
  probeSfxFiles()
  telem.init(state)

  if guihooks then
    guihooks.message("PlayerGuns loaded (" .. state.mountContext .. ")", 3, "playerGuns_init")
  end

  notifyInputBridge(true)
  publishHud()
end

-- Physics-step hook (2000 Hz). This is where bullet velocities are actually
-- set — applyForceVector forces last one physics step, so exact velocity
-- control is only possible here (same pattern as BeamNG's playerController
-- and stefan750's UniversalWeapons/Bell407 weapon controllers).
function M.update(dt)
  bullets.updatePhysics(state, dt)
end

function M.updateGFX(dt)
  state.isLocal = isLocalOwner()
  telem.update(state, dt)

  _diagFrameCount = _diagFrameCount + 1
  _diagSecondsAccum = _diagSecondsAccum + dt
  -- Heartbeat throttled to every 10s; per-shot detail lives in telemetry now.
  if _diagSecondsAccum >= 10.0 then
    log('I', 'playerGuns.tick', string.format(
      "mount=%s | local=%s | mpType=%s | seated=%s | aimLen=%.3f | pg_fire=%s | camCallbacks=%d | fireAttempts=%d | originNode=%s",
      state.mountContext,
      tostring(isLocalOwner()),
      tostring(v and v.mpVehicleType),
      tostring(playerInfo and playerInfo.anyPlayerSeated),
      state.aimDirection:length(),
      tostring(electrics.values.pg_fire),
      _diagCamCallbackCount,
      _diagFireAttempts,
      tostring(state.bulletOriginNodeName)
    ))
    _diagSecondsAccum = 0
    _diagFrameCount = 0
  end

  if isLocalOwner() then
    if vehicleSimStable() then
      state._aimAccum = (state._aimAccum or 0) + dt
      if state._aimAccum >= 0.033 then
        state._aimAccum = 0
        queueCameraAim()
      end
    elseif not state._loggedUnstable then
      state._loggedUnstable = true
      log('W', 'playerGuns.tick', 'Vehicle unstable — reset/repair vehicle (Ctrl+R) before PlayerGuns will aim or fire.')
    end
  else
    -- Remote (BeamMP): pg_aim_* carries the world target point. We honor the
    -- LOCAL owner's convergence preference (synced via pg_aim_converge_enabled
    -- electric) so remote bullets fly the same path the shooter saw.
    -- Mirror the shooter's weapon choice so replayed shots use its stats.
    local sel = math.floor(electrics.values.pg_selected_weapon or 1)
    if sel ~= state.selectedWeaponIdx and sel >= 1 and sel <= #weapons.list then
      state.selectedWeaponIdx = sel
    end
    local tx = electrics.values.pg_aim_x or 0
    local ty = electrics.values.pg_aim_y or 0
    local tz = electrics.values.pg_aim_z or 0
    state.aimTargetWorld = vec3(tx, ty, tz)
    local dir
    if (electrics.values.pg_aim_converge_enabled or 0) > 0.5 then
      dir = state.aimTargetWorld - bullets.muzzleWorldPos(state)
    else
      dir = vec3(electrics.values.pg_ray_dir_x or 0,
                 electrics.values.pg_ray_dir_y or 0,
                 electrics.values.pg_ray_dir_z or 0)
    end
    if dir:length() > 0.001 then state.aimDirection = dir:normalized() end
  end

  electrics.values.pg_gun_lift = (state.mountContext ~= 'roof') and min(0.9, max(-0.9, -state.aimDirection.z)) or 0

  state.recoilEnabled = (electrics.values.pg_recoil_enabled or 0) > 0.5

  bullets.updateBulletImpacts(state, weapons, state.selectedWeaponIdx, dt)
  bullets.recycleStrayBullets(state)
  applyWeaponStats()

  if not isLocalOwner() then
    local pulse = electrics.values.pg_fire_pulse or 0
    if M._lastSeenPulse == nil then M._lastSeenPulse = pulse end
    if pulse ~= M._lastSeenPulse then
      M._lastSeenPulse = pulse
      bullets.launchNextBullet(state, weapons, state.selectedWeaponIdx, state.aimDirection, _diagCamCallbackCount)
    end
    return
  end

  if (electrics.values.pg_reload or 0) > 0.9 then
    electrics.values.pg_reload = 0
    if _diagReloadPresses < 5 then
      _diagReloadPresses = _diagReloadPresses + 1
      log('I', 'playerGuns.reload', 'Reload #' .. _diagReloadPresses ..
          ' mount=' .. state.mountContext ..
          ' | reloading=' .. tostring(state.reloading) ..
          ' | magUsed=' .. tostring(state.magUsed[state.selectedWeaponIdx]))
    end
    if not state.reloading and state.magUsed[state.selectedWeaponIdx] > 0 then
      state.reloading = true
      state.reloadTimer = state.reloadTimeSec
      playReloadSound()
      publishHud()
    end
  end

  -- Weapon wheel: pg_wheel is 1 while the bind is held. Publish open/close to
  -- the UI app with the weapon list, so the wheel always matches weapons.lua.
  local wheelHeld = (electrics.values.pg_wheel or 0) > 0.5
  if wheelHeld ~= state._wheelOpen then
    state._wheelOpen = wheelHeld
    if guihooks and guihooks.trigger then
      local names = {}
      for i, w in ipairs(weapons.list) do names[i] = w.name end
      guihooks.trigger('playerGuns_wheel', {
        open = wheelHeld,
        weapons = names,
        current = state.selectedWeaponIdx,
      })
    end
  end

  if (electrics.values.pg_weaponUp or 0) > 0.9 then
    electrics.values.pg_weaponUp = 0
    if _diagSwitchPresses < 5 then
      _diagSwitchPresses = _diagSwitchPresses + 1
      log('I', 'playerGuns.switch', 'Next weapon #' .. _diagSwitchPresses .. ' mount=' .. state.mountContext)
    end
    switchWeapon(1)
  end
  if (electrics.values.pg_weaponDown or 0) > 0.9 then
    electrics.values.pg_weaponDown = 0
    if _diagSwitchPresses < 5 then
      _diagSwitchPresses = _diagSwitchPresses + 1
      log('I', 'playerGuns.switch', 'Prev weapon #' .. _diagSwitchPresses .. ' mount=' .. state.mountContext)
    end
    switchWeapon(-1)
  end

  if state.reloading then
    local nowFire = (electrics.values.pg_fire or 0)
    if nowFire > 0.9 and (M._lastFireValue or 0) < 0.9 and state.gunSoundNodeId then
      obj:playSFXOnce("CrashTestSound", state.gunSoundNodeId, 0.25, 0.4)
    end
    M._lastFireValue = nowFire

    state.reloadTimer = state.reloadTimer - dt
    if state.reloadTimer <= 0 then
      state.magUsed[state.selectedWeaponIdx] = 0
      state.reloading = false
      state.reloadTimer = 0
    end
    publishHud()
    return
  end
  M._lastFireValue = (electrics.values.pg_fire or 0)

  _hudRefreshAccum = _hudRefreshAccum + dt
  if _hudRefreshAccum >= 0.3 then
    publishHud()
    _hudRefreshAccum = 0
  end

  state.timeSinceLastShot = state.timeSinceLastShot + dt
  if state.timeSinceLastShot < state.fireDelaySec then return end
  if (electrics.values.pg_fire or 0) < 0.9 then return end
  if state._wheelOpen then return end

  _diagFireAttempts = _diagFireAttempts + 1
  if _diagFireAttempts <= 5 then
    log('I', 'playerGuns.fire', 'Fire #' .. _diagFireAttempts ..
        ' mount=' .. state.mountContext ..
        ' | aimLen=' .. tostring(state.aimDirection:length()) ..
        ' | mag=' .. tostring(state.magUsed[state.selectedWeaponIdx]) .. '/' .. tostring(state.magazineSize))
  end

  if state.magUsed[state.selectedWeaponIdx] >= state.magazineSize then
    if not state.reloading then
      state.reloading = true
      state.reloadTimer = state.reloadTimeSec
      playReloadSound()
      publishHud()
    end
    return
  end

  state.timeSinceLastShot = 0
  state.magUsed[state.selectedWeaponIdx] = state.magUsed[state.selectedWeaponIdx] + 1
  electrics.values.pg_fire_pulse = (electrics.values.pg_fire_pulse or 0) + 1
  bullets.launchNextBullet(state, weapons, state.selectedWeaponIdx, state.aimDirection, _diagCamCallbackCount)
  publishHud()
end

return M
