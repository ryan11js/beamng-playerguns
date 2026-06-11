-- Cross-vehicle impact damage dispatch for PlayerGuns.

local M = {}

local _diagImpactCount = 0

function M.resetDiagnostics()
  _diagImpactCount = 0
end

function M.notifyImpact(state, bulletNodeCid, selectedWeaponIdx, weapons)
  local localPos = obj:getNodePosition(bulletNodeCid)
  local vehiclePos = vec3(obj:getPosition())
  local wx = vehiclePos.x + localPos.x
  local wy = vehiclePos.y + localPos.y
  local wz = vehiclePos.z + localPos.z
  local radius = state.explosionRadius or 0.35
  local maxBreaks = state.maxBreaksPerHit or math.max(1, math.floor(state.bulletMass / 4))
  local force = state.blastForce or 0
  local ownId = obj:getID()

  _diagImpactCount = _diagImpactCount + 1
  -- Impact details now flow into telemetry; keep a handful of log lines only.
  local diagThisCall = _diagImpactCount <= 5
  if diagThisCall then
    log('I', 'playerGuns.impact', 'Impact #' .. _diagImpactCount ..
        ' weapon=' .. weapons.list[selectedWeaponIdx].name ..
        ' mount=' .. tostring(state.mountContext) ..
        ' world=' .. string.format('(%.2f,%.2f,%.2f)', wx, wy, wz) ..
        ' radius=' .. tostring(radius) ..
        ' maxBreaks=' .. tostring(maxBreaks) ..
        ' blastForce=' .. tostring(force) ..
        ' ownId=' .. tostring(ownId))
  end

  local diagTag = string.format('imp%d', _diagImpactCount)
  local damageCode = string.format(
    "local wx,wy,wz=%f,%f,%f local r2=%f local maxBreaks=%d local force=%f " ..
    "local tag=%q " ..
    "local vp=obj:getPosition() " ..
    "local lx,ly,lz=wx-vp.x,wy-vp.y,wz-vp.z " ..
    "local broken=0 local pressureBroken=0 " ..
    "local beamCount=0 " ..
    "if v and v.data and v.data.beams then for _ in pairs(v.data.beams) do beamCount=beamCount+1 end end " ..
    "local breakFn=(beamstate and beamstate.breakBeam) or function(cid) obj:breakBeam(cid) end " ..
    "local function beamInRange(b) " ..
      "if b.broken then return false end " ..
      "local n1=obj:getNodePosition(b.id1) " ..
      "local d1x,d1y,d1z=n1.x-lx,n1.y-ly,n1.z-lz " ..
      "if d1x*d1x+d1y*d1y+d1z*d1z<r2 then return true end " ..
      "local n2=obj:getNodePosition(b.id2) " ..
      "local d2x,d2y,d2z=n2.x-lx,n2.y-ly,n2.z-lz " ..
      "return d2x*d2x+d2y*d2y+d2z*d2z<r2 " ..
    "end " ..
    "for _,b in pairs(v.data.beams) do " ..
      "if broken>=maxBreaks then break end " ..
      "if b.beamType=='|PRESSURE' and beamInRange(b) then " ..
        "breakFn(b.cid) broken=broken+1 pressureBroken=pressureBroken+1 " ..
      "end " ..
    "end " ..
    "for _,b in pairs(v.data.beams) do " ..
      "if broken>=maxBreaks then break end " ..
      "if b.beamType~='|PRESSURE' and beamInRange(b) then " ..
        "breakFn(b.cid) broken=broken+1 " ..
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
    "log('I','playerGuns.target', 'tag='..tag..' beams='..beamCount..' broken='..broken..' pressure='..pressureBroken..' localPos=('..lx..','..ly..','..lz..')')",
    wx, wy, wz, radius * radius, maxBreaks, force, diagTag
  )

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

return M
