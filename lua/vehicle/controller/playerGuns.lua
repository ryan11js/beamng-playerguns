-- PlayerGuns vehicle controller (runs on the walking-mode unicycle).
--
-- Architecture is adapted from AgentY & AwesomeCarl's player_weapon_2 mod:
--   - Camera aim direction is fetched each frame via obj:queueGameEngineLua,
--     and bounced back to vehicle Lua through camForwardCallback().
--   - Bullets are physics nodes (pg_bullet001..100) defined in the ammo jbeam.
--     On fire, the next bullet is teleported to the gun, given mass, and
--     pushed with a force vector in the camera direction.
--   - Three weapons (Uzi / Thompson / AKM) live as a Lua state machine; no
--     per-weapon jbeam parts.
--
-- Multiplayer (BeamMP) extension on top of the pw2 design:
--   - Aim direction is written into electrics.values.pg_aim_x/y/z each frame.
--     BeamMP syncs electrics across clients, so a remote viewer can also see
--     the gun mesh rotate to where the shooter is aiming.
--   - Firing is gated to local-owned vehicles only. We use v.mpVehicleType (or
--     the synonyms BeamMP exposes) to detect ownership. Remote clients still
--     run the impact-particle update loop so visuals match, but the local
--     owner is the one applying force to bullets.

local M = {}

local min = math.min
local max = math.max
local abs = math.abs

-- ===== jbeam-loaded values =====
local totalBullets = 100
local fireParticleNodeInnerName = "bc1"
local fireParticleNodeOuterName = "pg_gun_node"
local gunSoundNodeName = "driver"
local bulletOriginNodeName = "driver"

-- ===== weapon state machine =====
local weapons = {
  {name = "Uzi",      fireDelaySec = 1/952*60, bulletVelocity = 1.4, bulletMass = 7,  magazineSize = 32, reloadTimeSec = 1.8},
  {name = "Thompson", fireDelaySec = 1/600*60, bulletVelocity = 1.9, bulletMass = 9,  magazineSize = 50, reloadTimeSec = 3.2},
  {name = "AKM",      fireDelaySec = 1/420*60, bulletVelocity = 2.8, bulletMass = 14, magazineSize = 30, reloadTimeSec = 2.7},
}
local selectedWeaponIdx = 1
local fireDelaySec = weapons[1].fireDelaySec
local bulletVelocity = weapons[1].bulletVelocity
local bulletMass = weapons[1].bulletMass
local magazineSize = weapons[1].magazineSize
local reloadTimeSec = weapons[1].reloadTimeSec

-- per-weapon magazine counts (so switching preserves state)
local magUsed = {0, 0, 0}

-- ===== runtime state =====
local currentBulletIdx = 1
local timeSinceLastShot = 0
local reloading = false
local reloadTimer = 0
local bulletsFired = 0
local aimDirection = vec3(0, 0, 0)

-- ===== diagnostic counters (debugging) =====
local _diagFrameCount = 0
local _diagSecondsAccum = 0
local _diagCamCallbackCount = 0
local _diagFireAttempts = 0
local _diagReloadPresses = 0
local _diagSwitchPresses = 0
local _hudRefreshAccum = 0

-- ===== node ids resolved at init =====
local gunSoundNodeId = nil
local fireParticleNodeInner = nil
local fireParticleNodeOuter = nil
local bulletOriginNodeId = nil

-- ===== MP ownership =====
local function isLocalOwner()
  -- BeamMP exposes v.mpVehicleType: "L" = local-owned, "R" = remote.
  -- Permissive: only return false if explicitly "R" (remote-owned). Anything
  -- else — nil (singleplayer), empty string, "?", "L" — is treated as local.
  if v and v.mpVehicleType then
    return v.mpVehicleType ~= "R"
  end
  return true
end

local function publishHud()
  local w = weapons[selectedWeaponIdx]
  local ammoLeft = max(0, w.magazineSize - magUsed[selectedWeaponIdx])
  local payload = {
    weapon = w.name,
    ammo = ammoLeft,
    mag = w.magazineSize,
    reserve = -1,
    reloading = reloading,
    reloadProgress = reloading and (1 - (reloadTimer / w.reloadTimeSec)) or 0,
  }
  -- Broadcast structured payload to the Angular HUD app via the guihooks→
  -- $rootScope bridge. The directive's scope.$on('playerGuns_hud', ...)
  -- only fires for guihooks.trigger, not gui.send (which is GE-side).
  if guihooks and guihooks.trigger then
    guihooks.trigger("playerGuns_hud", payload)
  end
  -- Toast fallback so weapon/ammo are visible without the HUD app added.
  if guihooks and guihooks.message then
    if reloading then
      guihooks.message(string.format("%s | Reloading %.1fs", w.name, max(0, reloadTimer)), 0.5, "playerGuns_status")
    else
      guihooks.message(string.format("%s | %d / %d", w.name, ammoLeft, w.magazineSize), 0.5, "playerGuns_status")
    end
  end
end

-- Apply a force to the next bullet, in the (synced) aim direction. Runs on
-- every client so the bullet nodes move in lock-step regardless of ownership.
local function launchNextBullet()
  if currentBulletIdx > totalBullets then
    currentBulletIdx = 1
  end

  local dir = aimDirection
  if dir:length() < 0.01 then
    log('W', 'playerGuns.launchNextBullet', 'BAIL: aimDirection length is zero — camera callback never delivered. cam-callback-count=' .. tostring(_diagCamCallbackCount))
    -- aim hasn't been received yet — bail rather than fire a zero-direction bullet.
    return
  end

  for _, node in pairs(v.data.nodes) do
    if node.pg_bulletID == currentBulletIdx then
      obj:setNodeMass(node.cid, bulletMass)
      obj:setNodePosition(node.cid, vec3(obj:getNodePosition(bulletOriginNodeId)))
      local force = dir * 900 * bulletVelocity + vec3(obj:getVelocity())
      obj:applyForceVector(node.cid, vec3(force))
      node.exploded = false
      break
    end
  end

  -- Muzzle particles + sound (every client plays these locally).
  if fireParticleNodeInner and fireParticleNodeOuter then
    obj:addParticleByNodesRelative(fireParticleNodeInner, fireParticleNodeOuter, 15, 61, 0, 1)
    obj:addParticleByNodesRelative(fireParticleNodeInner, fireParticleNodeOuter, 10, 62, 0, 1)
    obj:addParticleByNodesRelative(fireParticleNodeInner, fireParticleNodeOuter, 20, 63, 0, 1)
    obj:addParticleByNodesRelative(fireParticleNodeInner, fireParticleNodeOuter,  8, 64, 0, 1)
    obj:addParticleByNodesRelative(fireParticleNodeInner, fireParticleNodeOuter, 12, 65, 0, 1)
    if fireDelaySec >= 0.15 then
      obj:addParticleByNodesRelative(fireParticleNodeInner, fireParticleNodeOuter, 10, 6, 0, 1)
    end
  end
  if gunSoundNodeId then
    obj:playSFXOnce("CrashTestSound", gunSoundNodeId, 1, 2)
  end

  currentBulletIdx = currentBulletIdx + 1
  bulletsFired = bulletsFired + 1
end

-- Per-frame impact-particle update. Each fired bullet node is tracked: a sharp
-- drop in horizontal velocity = collision → emit particles, reset mass. This
-- is the same approach pw2 uses and runs on every client (purely visual).
local function updateBulletImpacts()
  for _, node in pairs(v.data.nodes) do
    if node.pg_bulletID and node.pg_bulletID < currentBulletIdx then
      if not node.exploded then
        obj:addParticleByNodesRelative(node.cid, node.cid, 1200000, 67, 0, 10)
      end
      local velocity = vec3(obj:getNodeVelocityVector(node.cid))
      if node.newHorizontalVelocity == nil then
        node.newHorizontalVelocity = abs(velocity.x) + abs(velocity.y)
      else
        node.horizontalVelocity = node.newHorizontalVelocity
        node.newHorizontalVelocity = abs(velocity.x) + abs(velocity.y)
        if not node.exploded and (node.horizontalVelocity - node.newHorizontalVelocity) > 0.01 then
          obj:addParticleByNodesRelative(node.cid, node.cid, 12, 1,  0.0002, 1)
          obj:addParticleByNodesRelative(node.cid, node.cid, 15, 61, 0.0002, 1)
          obj:addParticleByNodesRelative(node.cid, node.cid, 10, 62, 0.0002, 1)
          obj:addParticleByNodesRelative(node.cid, node.cid, 20, 63, 0.0002, 1)
          obj:addParticleByNodesRelative(node.cid, node.cid,  8, 64, 0.0002, 1)
          obj:addParticleByNodesRelative(node.cid, node.cid, 12, 65, 0.0002, 1)
          obj:addParticleByNodesRelative(node.cid, node.cid, 10,  6, 0.0002, 1)
          obj:setNodeMass(node.cid, 0.01)
          node.exploded = true
        end
      end
    end
  end
end

-- Recycle bullets that have flown off the world.
local function recycleStrayBullets()
  for _, node in pairs(v.data.nodes) do
    if node.pg_bulletID then
      local p = vec3(obj:getNodePosition(node.cid))
      if p.z < -500 or p.z > 500 then
        obj:setNodePosition(node.cid, vec3(obj:getNodePosition(bulletOriginNodeId)))
      end
    end
  end
end

local function applyWeaponStats()
  local w = weapons[selectedWeaponIdx]
  fireDelaySec   = w.fireDelaySec
  bulletVelocity = w.bulletVelocity
  bulletMass     = w.bulletMass
  magazineSize   = w.magazineSize
  reloadTimeSec  = w.reloadTimeSec
end

local function switchWeapon(direction)
  selectedWeaponIdx = selectedWeaponIdx + direction
  if selectedWeaponIdx > #weapons then selectedWeaponIdx = 1 end
  if selectedWeaponIdx < 1 then selectedWeaponIdx = #weapons end
  applyWeaponStats()
  if reloading then
    reloading = false
    reloadTimer = 0
  end
  electrics.values.pg_selected_weapon = selectedWeaponIdx
  publishHud()
end

local function camForwardCallback(fx, fy, fz)
  _diagCamCallbackCount = _diagCamCallbackCount + 1
  if _diagCamCallbackCount <= 3 then
    log('I', 'playerGuns.cam', 'camForwardCallback fired #' .. _diagCamCallbackCount ..
        ' fx=' .. tostring(fx) .. ' fy=' .. tostring(fy) .. ' fz=' .. tostring(fz))
  end
  aimDirection = vec3(fx, fy, fz)
  -- Publish to electrics so BeamMP syncs the aim direction to other clients.
  -- Remote viewers read these values to drive the gun's lift hydro.
  electrics.values.pg_aim_x = fx
  electrics.values.pg_aim_y = fy
  electrics.values.pg_aim_z = fz
end

local function updateGFX(dt)
  -- Diagnostic heartbeat: print state once per second.
  _diagFrameCount = _diagFrameCount + 1
  _diagSecondsAccum = _diagSecondsAccum + dt
  if _diagSecondsAccum >= 1.0 then
    log('I', 'playerGuns.tick', string.format(
      "updateGFX alive | frames=%d | local=%s | mpType=%s | aimLen=%.3f | pg_fire=%s | camCallbacks=%d | fireAttempts=%d",
      _diagFrameCount,
      tostring(isLocalOwner()),
      tostring(v and v.mpVehicleType),
      aimDirection:length(),
      tostring(electrics.values.pg_fire),
      _diagCamCallbackCount,
      _diagFireAttempts
    ))
    _diagSecondsAccum = 0
    _diagFrameCount = 0
  end

  -- 1) Pull camera forward from GE and bounce it back here. Local-only — on
  --    remote clients, aimDirection is hydrated from synced electrics below.
  if isLocalOwner() then
    obj:queueGameEngineLua(
      "local f = core_camera.getForward() " ..
      "be:getObjectByID(" .. obj:getID() ..
      "):queueLuaCommand(\"controller.getControllerSafe('playerGuns').camForwardCallback(\" .. " ..
      "tostring(f.x) .. \", \" .. tostring(f.y) .. \", \" .. tostring(f.z) .. \")\")"
    )
  else
    -- Remote client: read synced aim direction from electrics.
    local ax = electrics.values.pg_aim_x or 0
    local ay = electrics.values.pg_aim_y or 0
    local az = electrics.values.pg_aim_z or 0
    aimDirection = vec3(ax, ay, az)
  end

  -- 2) Drive the gun-lift hydro so the gun mesh follows pitch (works on all clients).
  electrics.values.pg_gun_lift = min(0.9, max(-0.9, -aimDirection.z))

  -- 3) Per-frame impact particles for fired bullets.
  updateBulletImpacts()

  -- 4) Recycle strays.
  recycleStrayBullets()

  -- 5) Apply weapon stats (cheap; keeps state coherent if jbeamData ever changes).
  applyWeaponStats()

  -- 6) Remote-client path: just replay synced fire pulses, no input handling.
  if not isLocalOwner() then
    local pulse = electrics.values.pg_fire_pulse or 0
    if M._lastSeenPulse == nil then M._lastSeenPulse = pulse end
    if pulse ~= M._lastSeenPulse then
      M._lastSeenPulse = pulse
      launchNextBullet()
    end
    return
  end

  -- 7) INPUT HANDLING — runs every frame, even mid-reload. Manual reload and
  --    weapon switches must always be reachable; previous version's "return
  --    while reloading" blocked them during the 1.8s auto-reload window.

  -- Reload request.
  if (electrics.values.pg_reload or 0) > 0.9 then
    electrics.values.pg_reload = 0
    if _diagReloadPresses < 5 then
      _diagReloadPresses = _diagReloadPresses + 1
      log('I', 'playerGuns.reload', 'Reload key detected #' .. _diagReloadPresses ..
          ' | reloading=' .. tostring(reloading) ..
          ' | magUsed=' .. tostring(magUsed[selectedWeaponIdx]) ..
          ' | magSize=' .. tostring(magazineSize))
    end
    if not reloading and magUsed[selectedWeaponIdx] > 0 then
      reloading = true
      reloadTimer = reloadTimeSec
      publishHud()
    end
  end

  -- Weapon switch — cancels in-progress reload (matches pw2 behavior).
  if (electrics.values.pg_weaponUp or 0) > 0.9 then
    electrics.values.pg_weaponUp = 0
    if _diagSwitchPresses < 5 then
      _diagSwitchPresses = _diagSwitchPresses + 1
      log('I', 'playerGuns.switch', 'Next-weapon key detected #' .. _diagSwitchPresses ..
          ' | from=' .. weapons[selectedWeaponIdx].name)
    end
    switchWeapon(1)
  end
  if (electrics.values.pg_weaponDown or 0) > 0.9 then
    electrics.values.pg_weaponDown = 0
    if _diagSwitchPresses < 5 then
      _diagSwitchPresses = _diagSwitchPresses + 1
      log('I', 'playerGuns.switch', 'Prev-weapon key detected #' .. _diagSwitchPresses ..
          ' | from=' .. weapons[selectedWeaponIdx].name)
    end
    switchWeapon(-1)
  end

  -- 8) Reload tick (runs AFTER input so manual reload/switch is always reachable).
  if reloading then
    reloadTimer = reloadTimer - dt
    if reloadTimer <= 0 then
      magUsed[selectedWeaponIdx] = 0
      reloading = false
      reloadTimer = 0
    end
    -- Publish every frame during reload so the progress bar and countdown
    -- text animate smoothly. CSS transition in the directive smooths jitter.
    publishHud()
    return  -- still can't fire while reloading
  end

  -- 9) Periodic HUD refresh so the guihooks toast stays visible even when
  --    no state change is happening (publishHud's TTL is 0.5s).
  _hudRefreshAccum = _hudRefreshAccum + dt
  if _hudRefreshAccum >= 0.3 then
    publishHud()
    _hudRefreshAccum = 0
  end

  -- Firing.
  timeSinceLastShot = timeSinceLastShot + dt
  if timeSinceLastShot < fireDelaySec then return end
  if (electrics.values.pg_fire or 0) < 0.9 then return end
  _diagFireAttempts = _diagFireAttempts + 1
  if _diagFireAttempts <= 5 then
    log('I', 'playerGuns.fire', 'Fire input detected #' .. _diagFireAttempts ..
        ' | pg_fire=' .. tostring(electrics.values.pg_fire) ..
        ' | aimLen=' .. tostring(aimDirection:length()) ..
        ' | mag=' .. tostring(magUsed[selectedWeaponIdx]) .. '/' .. tostring(magazineSize))
  end
  if magUsed[selectedWeaponIdx] >= magazineSize then
    -- empty mag — could play empty-click sound here; auto-reload feels better.
    if not reloading then
      reloading = true
      reloadTimer = reloadTimeSec
      publishHud()
    end
    return
  end

  timeSinceLastShot = 0
  magUsed[selectedWeaponIdx] = magUsed[selectedWeaponIdx] + 1
  -- Pulse the fire signal so remote clients replay the shot.
  electrics.values.pg_fire_pulse = (electrics.values.pg_fire_pulse or 0) + 1
  launchNextBullet()
  publishHud()
end

local function init(jbeamData)
  -- Loud init markers so we can confirm the controller is actually loading.
  log('I', 'playerGuns.init', '=========================================')
  log('I', 'playerGuns.init', 'PlayerGuns controller init() called')
  log('I', 'playerGuns.init', 'jbeamData.totalBullets = ' .. tostring(jbeamData.totalBullets))
  log('I', 'playerGuns.init', 'jbeamData.magazineSize = ' .. tostring(jbeamData.magazineSize))
  log('I', 'playerGuns.init', '=========================================')
  if guihooks then
    guihooks.message("PlayerGuns controller loaded", 3, "playerGuns_init")
  end

  totalBullets = jbeamData.totalBullets or 100

  -- Resolve node ids.
  gunSoundNodeId = nil
  fireParticleNodeInner = nil
  fireParticleNodeOuter = nil
  bulletOriginNodeId = nil
  for _, node in pairs(v.data.nodes) do
    if node.name == gunSoundNodeName then gunSoundNodeId = node.cid end
    if node.name == fireParticleNodeInnerName then fireParticleNodeInner = node.cid end
    if node.name == fireParticleNodeOuterName then fireParticleNodeOuter = node.cid end
    if node.name == bulletOriginNodeName then bulletOriginNodeId = node.cid end
    -- reset bullet impact state
    if node.pg_bulletID then
      node.horizontalVelocity = nil
      node.newHorizontalVelocity = nil
      node.exploded = false
    end
  end

  if not bulletOriginNodeId and fireParticleNodeOuter then
    bulletOriginNodeId = fireParticleNodeOuter
  end

  -- Reset electrics.
  electrics.values.pg_fire = 0
  electrics.values.pg_reload = 0
  electrics.values.pg_weaponUp = 0
  electrics.values.pg_weaponDown = 0
  electrics.values.pg_gun_lift = 0
  electrics.values.pg_fire_pulse = 0
  electrics.values.pg_aim_x = 0
  electrics.values.pg_aim_y = 0
  electrics.values.pg_aim_z = 0
  electrics.values.pg_selected_weapon = 1

  -- Reset state.
  selectedWeaponIdx = 1
  applyWeaponStats()
  magUsed = {0, 0, 0}
  currentBulletIdx = 1
  timeSinceLastShot = 0
  reloading = false
  reloadTimer = 0
  bulletsFired = 0
  _diagReloadPresses = 0
  _diagSwitchPresses = 0
  _hudRefreshAccum = 0
  aimDirection = vec3(0, 0, 0)
  M._lastSeenPulse = 0

  publishHud()
end

-- Public interface.
M.init = init
M.updateGFX = updateGFX
M.camForwardCallback = camForwardCallback
M.switchWeapon = switchWeapon

return M
