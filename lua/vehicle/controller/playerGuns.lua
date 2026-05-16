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
-- spreadDeg = half-angle of the recoil cone, degrees. 0 = pixel-perfect.
-- isExplosive = bullet does AoE damage on impact instead of point-damage.
-- explosionRadius = damage radius on hit (meters). Default 0.35 for ballistic.
-- maxBreaksPerHit = max beams the impact breaks on target vehicles per round.
-- fireSoundPitch / fireSoundVolume = pitch/volume of CrashTestSound at fire.
--   Pitch varies per weapon to give audio character without shipping OGGs;
--   drop a real per-weapon sound in vehicles/unicycle/sounds/ later and
--   replace "CrashTestSound" with the file path in launchNextBullet.
-- meshName: collada mesh name in playerGuns_models.dae; used for setMeshAlpha.
-- hasMuzzleSmoke: false suppresses the slow-fire smoke puff in launchNextBullet.
local weapons = {
  {name = "Pistol",   meshName = "unicycle_pistol",  hasMuzzleSmoke = false, fireDelaySec = 0.18,     bulletVelocity = 1.3, bulletMass = 6,  magazineSize = 12,  reloadTimeSec = 1.5, spreadDeg = 1.5, isExplosive = false, explosionRadius = 0.30, maxBreaksPerHit = 1,  blastForce = 0,     fireSoundPitch = 2.2, fireSoundVolume = 0.7},
  {name = "Uzi",      meshName = "unicycle_uzi",     hasMuzzleSmoke = true,  fireDelaySec = 1/952*60, bulletVelocity = 1.4, bulletMass = 7,  magazineSize = 32,  reloadTimeSec = 1.8, spreadDeg = 7.0, isExplosive = false, explosionRadius = 0.35, maxBreaksPerHit = 2,  blastForce = 0,     fireSoundPitch = 2.5, fireSoundVolume = 0.8},
  {name = "Thompson", meshName = "unicycle_tom",     hasMuzzleSmoke = true,  fireDelaySec = 1/600*60, bulletVelocity = 1.9, bulletMass = 9,  magazineSize = 50,  reloadTimeSec = 3.2, spreadDeg = 4.5, isExplosive = false, explosionRadius = 0.35, maxBreaksPerHit = 2,  blastForce = 0,     fireSoundPitch = 1.8, fireSoundVolume = 1.0},
  {name = "AKM",      meshName = "unicycle_akm",     hasMuzzleSmoke = true,  fireDelaySec = 1/420*60, bulletVelocity = 2.8, bulletMass = 14, magazineSize = 30,  reloadTimeSec = 2.7, spreadDeg = 3.0, isExplosive = false, explosionRadius = 0.40, maxBreaksPerHit = 4,  blastForce = 0,     fireSoundPitch = 1.5, fireSoundVolume = 1.1},
  {name = "Sniper",   meshName = "unicycle_awp",     hasMuzzleSmoke = true,  fireDelaySec = 1.4,      bulletVelocity = 4.5, bulletMass = 60, magazineSize = 5,   reloadTimeSec = 3.0, spreadDeg = 0.0, isExplosive = false, explosionRadius = 0.50, maxBreaksPerHit = 12, blastForce = 0,     fireSoundPitch = 0.9, fireSoundVolume = 1.4},
  {name = "Minigun",  meshName = "unicycle_minigun", hasMuzzleSmoke = true,  fireDelaySec = 0.04,     bulletVelocity = 1.7, bulletMass = 8,  magazineSize = 250, reloadTimeSec = 4.5, spreadDeg = 5.5, isExplosive = false, explosionRadius = 0.35, maxBreaksPerHit = 2,  blastForce = 0,     fireSoundPitch = 2.7, fireSoundVolume = 0.95},
  {name = "Bazooka",  meshName = "unicycle_bazooka", hasMuzzleSmoke = true,  fireDelaySec = 1.0,      bulletVelocity = 2.5, bulletMass = 80, magazineSize = 1,   reloadTimeSec = 3.0, spreadDeg = 1.0, isExplosive = true,  explosionRadius = 4.0,  maxBreaksPerHit = 120, blastForce = 80000, fireSoundPitch = 0.7, fireSoundVolume = 1.6},
}
local selectedWeaponIdx = 1
local fireDelaySec = weapons[1].fireDelaySec
local bulletVelocity = weapons[1].bulletVelocity
local bulletMass = weapons[1].bulletMass
local magazineSize = weapons[1].magazineSize
local reloadTimeSec = weapons[1].reloadTimeSec
local spreadDeg = weapons[1].spreadDeg
local isExplosive = weapons[1].isExplosive
local explosionRadius = weapons[1].explosionRadius
local maxBreaksPerHit = weapons[1].maxBreaksPerHit
local fireSoundPitch = weapons[1].fireSoundPitch
local fireSoundVolume = weapons[1].fireSoundVolume
local blastForce = weapons[1].blastForce or 0
local hasMuzzleSmoke = weapons[1].hasMuzzleSmoke ~= false

-- per-weapon magazine counts (so switching preserves state)
local magUsed = {0, 0, 0, 0, 0, 0, 0}

-- ===== runtime state =====
local currentBulletIdx = 1
local timeSinceLastShot = 0
local reloading = false
local reloadTimer = 0
local bulletsFired = 0
local aimDirection = vec3(0, 0, 0)
-- Reload sound: played via GE-side Engine.Audio.playOnce one-shot (not a
-- pre-created SFX source — those auto-looped and caused a "humming" bug).

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

  -- Apply per-weapon recoil: jitter aim direction within a cone of half-angle
  -- spreadDeg around the camera-forward vector. Uses two random axes built
  -- from world up; for near-vertical aim the cone collapses but that's fine
  -- since the player is unlikely to fire straight up.
  if spreadDeg and spreadDeg > 0 then
    local up = vec3(0, 0, 1)
    local right = dir:cross(up)
    if right:length() < 0.001 then right = vec3(1, 0, 0) end
    right = right:normalized()
    local upPerp = right:cross(dir):normalized()
    local rad = spreadDeg * math.pi / 180
    -- Uniform sample inside a disc, then project onto the cone surface.
    local theta = math.random() * 2 * math.pi
    local r = math.sqrt(math.random()) * math.tan(rad)
    local jitter = right * (r * math.cos(theta)) + upPerp * (r * math.sin(theta))
    dir = (dir + jitter):normalized()
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
    -- Slow-firing weapons get a muzzle smoke puff. Pistol opts out explicitly
    -- via hasMuzzleSmoke=false (user feedback: pistol smoke looked out of place).
    if hasMuzzleSmoke and fireDelaySec >= 0.15 then
      obj:addParticleByNodesRelative(fireParticleNodeInner, fireParticleNodeOuter, 10, 6, 0, 1)
    end
  end
  if gunSoundNodeId then
    obj:playSFXOnce("CrashTestSound", gunSoundNodeId, fireSoundVolume, fireSoundPitch)
  end

  currentBulletIdx = currentBulletIdx + 1
  bulletsFired = bulletsFired + 1
end

-- Broadcast an impact to all nearby vehicles. Used to make bullets actually
-- damage things (pop tires, break panels) instead of bouncing off.
--
-- We can't assume the TARGET vehicle has any of our code installed, so the
-- damage logic is inlined as a self-contained Lua string that gets sent via
-- queueLuaCommand. Each target vehicle iterates its own beams, finds the ones
-- whose endpoint is within the damage radius of the impact point, and breaks
-- them via the built-in obj:breakBeam. Tires depressurize naturally once any
-- of their pressure beams break.
local _diagImpactCount = 0
local function notifyImpact(bulletNodeCid)
  local localPos = obj:getNodePosition(bulletNodeCid)
  local vehiclePos = vec3(obj:getPosition())
  local wx = vehiclePos.x + localPos.x
  local wy = vehiclePos.y + localPos.y
  local wz = vehiclePos.z + localPos.z
  local radius = explosionRadius or 0.35
  local maxBreaks = maxBreaksPerHit or math.max(1, math.floor(bulletMass / 4))
  local force = blastForce or 0
  local ownId = obj:getID()

  _diagImpactCount = _diagImpactCount + 1
  local diagThisCall = _diagImpactCount <= 10
  if diagThisCall then
    log('I', 'playerGuns.impact', 'Impact #' .. _diagImpactCount ..
        ' weapon=' .. weapons[selectedWeaponIdx].name ..
        ' world=' .. string.format('(%.2f,%.2f,%.2f)', wx, wy, wz) ..
        ' radius=' .. tostring(radius) ..
        ' maxBreaks=' .. tostring(maxBreaks) ..
        ' blastForce=' .. tostring(force) ..
        ' ownId=' .. tostring(ownId))
  end

  -- Per-target damage code. Runs inside the TARGET vehicle's Lua context.
  -- Uses beamstate.breakBeam (not obj:breakBeam) so pressure beams on tires
  -- depressurize correctly. Falls back to obj:breakBeam if beamstate isn't
  -- available (some controllerless vehicles). Also iterates BOTH endpoints
  -- of each beam (id1 AND id2) so a bullet hitting near the outer rim node
  -- still breaks the air beam to the inner rim node.
  --
  -- If blastForce > 0 (explosive round), apply an outward push to each node
  -- within the radius using obj:applyForceVector.
  -- Diagnostic: target vehicle prints how many beams it broke. The DIAG
  -- placeholder is filled with a tag string GE-side knows about so we can
  -- correlate "GE dispatched to N targets" vs "M of them actually ran the
  -- damage code".
  local diagTag = string.format('imp%d', _diagImpactCount)
  local damageCode = string.format(
    "local wx,wy,wz=%f,%f,%f local r2=%f local maxBreaks=%d local force=%f " ..
    "local tag=%q " ..
    "local vp=obj:getPosition() " ..
    "local lx,ly,lz=wx-vp.x,wy-vp.y,wz-vp.z " ..
    "local broken=0 " ..
    "local beamCount=0 " ..
    "if v and v.data and v.data.beams then for _ in pairs(v.data.beams) do beamCount=beamCount+1 end end " ..
    "local breakFn=(beamstate and beamstate.breakBeam) or function(cid) obj:breakBeam(cid) end " ..
    "for _,b in pairs(v.data.beams) do " ..
      "if broken>=maxBreaks then break end " ..
      "if not b.broken then " ..
        "local n1=obj:getNodePosition(b.id1) " ..
        "local d1x,d1y,d1z=n1.x-lx,n1.y-ly,n1.z-lz " ..
        "local hit=(d1x*d1x+d1y*d1y+d1z*d1z<r2) " ..
        "if not hit then " ..
          "local n2=obj:getNodePosition(b.id2) " ..
          "local d2x,d2y,d2z=n2.x-lx,n2.y-ly,n2.z-lz " ..
          "hit=(d2x*d2x+d2y*d2y+d2z*d2z<r2) " ..
        "end " ..
        "if hit then breakFn(b.cid) broken=broken+1 end " ..
      "end " ..
    "end " ..
    "if force>0 then " ..
      "for _,n in pairs(v.data.nodes) do " ..
        "local np=obj:getNodePosition(n.cid) " ..
        "local dx,dy,dz=np.x-lx,np.y-ly,np.z-lz " ..
        "local d2=dx*dx+dy*dy+dz*dz " ..
        "if d2<r2 and d2>0.0001 then " ..
          "local d=math.sqrt(d2) " ..
          "local falloff=1-(d/math.sqrt(r2)) " ..
          "local f=force*falloff/d " ..
          "obj:applyForceVector(n.cid, vec3(dx*f, dy*f, dz*f)) " ..
        "end " ..
      "end " ..
    "end " ..
    "log('I','playerGuns.target', 'tag='..tag..' beams='..beamCount..' broken='..broken..' localPos=('..lx..','..ly..','..lz..')')",
    wx, wy, wz, radius * radius, maxBreaks, force, diagTag
  )

  -- GE-side dispatcher: find nearby other vehicles and queue the damage code
  -- on each. Coarse pre-filter uses (radius+5m)^2 so the per-vehicle damage
  -- code only runs for plausibly-affected targets. Explosive rounds cast a
  -- wider net than ballistic rounds.
  -- Uses be:getObjectCount()+be:getObject(i) (the documented GE iteration API).
  -- The previous be:getObjectIDs() was a non-existent method that crashed Lua.
  local coarseDist2 = (radius + 5) * (radius + 5)
  local diagFlag = diagThisCall and 1 or 0
  local geCmd = string.format(
    [[(function()
        local wp = vec3(%f, %f, %f)
        local code = %q
        local maxD2 = %f
        local ownId = %d
        local diag = %d
        local tag = %q
        local count = be:getObjectCount()
        local examined, dispatched = 0, 0
        local skippedSelf, skippedNoCmd, skippedFar = 0, 0, 0
        for i = 0, count-1 do
          local vobj = be:getObject(i)
          if vobj and vobj.getID then
            examined = examined + 1
            local oid = vobj:getID()
            if oid == ownId then
              skippedSelf = skippedSelf + 1
            elseif not vobj.queueLuaCommand then
              skippedNoCmd = skippedNoCmd + 1
            else
              local vp = vobj:getPosition()
              local dx, dy, dz = wp.x - vp.x, wp.y - vp.y, wp.z - vp.z
              local d2 = dx*dx + dy*dy + dz*dz
              if d2 < maxD2 then
                vobj:queueLuaCommand(code)
                dispatched = dispatched + 1
                if diag == 1 then
                  log('I','playerGuns.dispatch','tag='..tag..' -> target id='..oid..' dist='..math.sqrt(d2))
                end
              else
                skippedFar = skippedFar + 1
              end
            end
          end
        end
        if diag == 1 then
          log('I','playerGuns.geImpact','tag='..tag..' examined='..examined..' dispatched='..dispatched..' skipSelf='..skippedSelf..' skipNoCmd='..skippedNoCmd..' skipFar='..skippedFar..' coarseRadius='..math.sqrt(maxD2))
        end
      end)()]],
    wx, wy, wz, damageCode, coarseDist2, ownId, diagFlag, diagTag
  )
  obj:queueGameEngineLua(geCmd)
end

-- Per-frame impact-particle update. Each fired bullet node is tracked: a sharp
-- drop in horizontal velocity = collision → emit particles, reset mass, and
-- broadcast damage to whatever vehicle was hit.
local function updateBulletImpacts()
  for _, node in pairs(v.data.nodes) do
    if node.pg_bulletID and node.pg_bulletID < currentBulletIdx then
      if not node.exploded then
        -- Smoke trail (subtle, persists)
        obj:addParticleByNodesRelative(node.cid, node.cid, 1200000, 67, 0, 10)
        -- Bright tracer streak — fire particle pointing backward toward the
        -- gun so the streak trails the bullet (node1->node2 is the direction).
        if bulletOriginNodeId then
          obj:addParticleByNodesRelative(node.cid, bulletOriginNodeId, 1200000, 9, 0, 2)
          obj:addParticleByNodesRelative(node.cid, bulletOriginNodeId, 1200000, 61, 0, 1)
        end
      end
      local velocity = vec3(obj:getNodeVelocityVector(node.cid))
      if node.newHorizontalVelocity == nil then
        node.newHorizontalVelocity = abs(velocity.x) + abs(velocity.y)
      else
        node.horizontalVelocity = node.newHorizontalVelocity
        node.newHorizontalVelocity = abs(velocity.x) + abs(velocity.y)
        if not node.exploded and (node.horizontalVelocity - node.newHorizontalVelocity) > 0.01 then
          if isExplosive then
            -- Bigger fireball + smoke for explosive rounds (bazooka, etc.).
            -- Particle IDs cribbed from pw2's RPG handler (lua/vehicle/controller/pw2.lua:290-292).
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
          obj:setNodeMass(node.cid, 0.01)
          node.exploded = true
          -- Broadcast damage to nearby vehicles (pops tires, breaks panels).
          notifyImpact(node.cid)
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

-- Push setMeshAlpha calls to the GE side. Hides every weapon mesh except the
-- active one. Built lazily because applyWeaponStats runs every frame; only the
-- weapon-index transitions actually rebuild the script.
local _lastVisibilityIdx = nil
local function applyMeshVisibility()
  if _lastVisibilityIdx == selectedWeaponIdx then return end
  _lastVisibilityIdx = selectedWeaponIdx
  local id = obj:getID()
  -- Build a single GE-side script that grabs the vehicle by id and sets alpha
  -- on each weapon mesh in turn. The third arg (`false`) means non-recursive.
  local parts = {string.format("local v = be:getObjectByID(%d) if not v or not v.setMeshAlpha then return end ", id)}
  for i, w in ipairs(weapons) do
    local a = (i == selectedWeaponIdx) and 1 or 0
    parts[#parts+1] = string.format("v:setMeshAlpha(%d, '%s', false) ", a, w.meshName)
  end
  obj:queueGameEngineLua(table.concat(parts))
  log('I', 'playerGuns.visibility', 'setMeshAlpha applied for weapon=' .. weapons[selectedWeaponIdx].name)
end

local function applyWeaponStats()
  local w = weapons[selectedWeaponIdx]
  fireDelaySec    = w.fireDelaySec
  bulletVelocity  = w.bulletVelocity
  bulletMass      = w.bulletMass
  magazineSize    = w.magazineSize
  reloadTimeSec   = w.reloadTimeSec
  spreadDeg       = w.spreadDeg or 0
  isExplosive     = w.isExplosive or false
  explosionRadius = w.explosionRadius or 0.35
  maxBreaksPerHit = w.maxBreaksPerHit or 2
  fireSoundPitch  = w.fireSoundPitch or 2
  fireSoundVolume = w.fireSoundVolume or 1
  blastForce      = w.blastForce or 0
  hasMuzzleSmoke  = w.hasMuzzleSmoke ~= false
  -- Drive per-weapon prop visibility (defensive translation hack — primary
  -- visibility is `setMeshAlpha` from applyMeshVisibility). One electric per
  -- weapon; the active weapon's prop sits at baseTranslation, all others get
  -- shoved 1km away (see playerGuns_main.jbeam props for the math).
  -- Order MUST match the weapons table above (Pistol=1..Bazooka=7).
  electrics.values.pg_show_pistol  = (selectedWeaponIdx == 1) and 1 or 0
  electrics.values.pg_show_uzi     = (selectedWeaponIdx == 2) and 1 or 0
  electrics.values.pg_show_tom     = (selectedWeaponIdx == 3) and 1 or 0
  electrics.values.pg_show_akm     = (selectedWeaponIdx == 4) and 1 or 0
  electrics.values.pg_show_sniper  = (selectedWeaponIdx == 5) and 1 or 0
  electrics.values.pg_show_minigun = (selectedWeaponIdx == 6) and 1 or 0
  electrics.values.pg_show_bazooka = (selectedWeaponIdx == 7) and 1 or 0
  applyMeshVisibility()
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
      obj:queueGameEngineLua("Engine.Audio.playOnce('AudioGui', '/vehicles/unicycle/sounds/playerGuns_reload.wav')")
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
    -- Empty-click feedback: edge-trigger when fire is pressed mid-reload.
    -- Uses the same sound at low volume + low pitch for a "dud" feel.
    local nowFire = (electrics.values.pg_fire or 0)
    if nowFire > 0.9 and (M._lastFireValue or 0) < 0.9 and gunSoundNodeId then
      obj:playSFXOnce("CrashTestSound", gunSoundNodeId, 0.25, 0.4)
    end
    M._lastFireValue = nowFire

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
  M._lastFireValue = (electrics.values.pg_fire or 0)

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
    -- empty mag — auto-reload kicks in immediately for fluid feel.
    if not reloading then
      reloading = true
      reloadTimer = reloadTimeSec
      obj:queueGameEngineLua("Engine.Audio.playOnce('AudioGui', '/vehicles/unicycle/sounds/playerGuns_reload.wav')")
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
  _lastVisibilityIdx = nil  -- force setMeshAlpha to re-run after respawn
  applyWeaponStats()
  magUsed = {0, 0, 0, 0, 0, 0, 0}
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
