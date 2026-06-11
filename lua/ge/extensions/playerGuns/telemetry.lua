-- PlayerGuns telemetry recorder (GE side).
--
-- Collects compact events pushed from the vehicle controller (shots, trajectory
-- samples, impacts, mount sag) and aggregates them into per-minute buckets so a
-- whole test session can be reviewed from ONE small JSON file instead of
-- grepping beamng.log.
--
-- Dump from the console:   extensions.playerGuns_telemetry.dump()
-- Output file:             settings/playerGuns/telemetry.json  (in the userfolder)

local M = {}

local SELF_HIT_RADIUS = 6.0   -- impact closer than this (m) to the firing vehicle counts as a self-hit
local RECENT_CAP = 120        -- ring buffer of recent event strings
local WORST_CAP = 8           -- worst trajectory-error shots kept
local DUMP_PATH = 'settings/playerGuns/telemetry.json'
local UI_INTERVAL = 0.5

local enabled = true
local sessionSec = 0
local _uiAccum = 0

local totals = {}
local perMinute = {}   -- [minuteIdx] = bucket
local recent = {}      -- ring buffer of compact strings
local recentHead = 0
local worstShots = {}

local function newBucket(m)
  return { m = m, shots = 0, impacts = 0, selfHits = 0, bails = 0, hotReuse = 0,
           trajN = 0, trajSum = 0, trajMax = 0, spdSum = 0,
           vertSum = 0, latSum = 0, sagMax = 0 }
end

local function resetData()
  sessionSec = 0
  totals = { shots = 0, impacts = 0, selfHits = 0, bails = 0, hotReuse = 0,
             trajN = 0, trajSum = 0, trajMax = 0, spdSum = 0,
             vertSum = 0, latSum = 0, sagMax = 0, sagNow = 0 }
  perMinute = {}
  recent = {}
  recentHead = 0
  worstShots = {}
end
resetData()

local function bucket()
  local m = math.floor(sessionSec / 60)
  local b = perMinute[m]
  if not b then
    b = newBucket(m)
    perMinute[m] = b
  end
  return b
end

local function pushRecent(str)
  recentHead = (recentHead % RECENT_CAP) + 1
  recent[recentHead] = string.format('t=%.1f %s', sessionSec, str)
end

local function noteWorst(entry)
  worstShots[#worstShots + 1] = entry
  table.sort(worstShots, function(a, b) return a.errDeg > b.errDeg end)
  while #worstShots > WORST_CAP do table.remove(worstShots) end
end

-- ---------------------------------------------------------------------------
-- Event sinks (called from vehicle Lua via queueGameEngineLua)
-- ---------------------------------------------------------------------------

function M.evShot(vehId, shotNo, weaponIdx, hotReuse, staleSpd)
  if not enabled then return end
  totals.shots = totals.shots + 1
  local b = bucket()
  b.shots = b.shots + 1
  if (hotReuse or 0) > 0 then
    totals.hotReuse = totals.hotReuse + 1
    b.hotReuse = b.hotReuse + 1
    if (staleSpd or 0) > 30 then
      pushRecent(string.format('HOT-REUSE shot=%d staleVel=%.0fm/s (all 100 nodes airborne)', shotNo, staleSpd))
    end
  end
end

-- sampleIdx 1 = ~0.05s after launch (launch quality), 2 = ~0.15s (in-flight).
-- Aggregates use sample 1 only so drag/gravity droop doesn't pollute the
-- launch-error metric; sample-2 detail still lands in recent/worst lists.
function M.evTraj(vehId, shotNo, errDeg, speed, sampleIdx, vertDeg, latDeg)
  if not enabled then return end
  sampleIdx = sampleIdx or 1
  if sampleIdx == 1 then
    totals.trajN = totals.trajN + 1
    totals.trajSum = totals.trajSum + errDeg
    totals.spdSum = totals.spdSum + (speed or 0)
    totals.vertSum = totals.vertSum + math.abs(vertDeg or 0)
    totals.latSum = totals.latSum + math.abs(latDeg or 0)
    if errDeg > totals.trajMax then totals.trajMax = errDeg end
    local b = bucket()
    b.trajN = b.trajN + 1
    b.trajSum = b.trajSum + errDeg
    b.spdSum = b.spdSum + (speed or 0)
    b.vertSum = b.vertSum + math.abs(vertDeg or 0)
    b.latSum = b.latSum + math.abs(latDeg or 0)
    if errDeg > b.trajMax then b.trajMax = errDeg end
  end
  if errDeg > 5 then
    pushRecent(string.format('TRAJ shot=%d s%d err=%.1f vert=%.1f lat=%.1f speed=%.0fm/s',
      shotNo, sampleIdx, errDeg, vertDeg or 0, latDeg or 0, speed))
    if sampleIdx == 1 then
      noteWorst({ n = shotNo, errDeg = math.floor(errDeg * 10) / 10,
                  vert = math.floor((vertDeg or 0) * 10) / 10,
                  lat = math.floor((latDeg or 0) * 10) / 10,
                  speed = math.floor(speed), t = math.floor(sessionSec) })
    end
  end
end

function M.evImpact(vehId, shotNo, distFromVeh, flightSec)
  if not enabled then return end
  totals.impacts = totals.impacts + 1
  local b = bucket()
  b.impacts = b.impacts + 1
  if distFromVeh < SELF_HIT_RADIUS then
    totals.selfHits = totals.selfHits + 1
    b.selfHits = b.selfHits + 1
    pushRecent(string.format('SELF-HIT shot=%d dist=%.1fm flight=%.2fs', shotNo, distFromVeh, flightSec))
  end
end

function M.evSag(vehId, sagMeters, tiltDeg)
  if not enabled then return end
  totals.sagNow = sagMeters
  if sagMeters > totals.sagMax then totals.sagMax = sagMeters end
  totals.tiltNow = tiltDeg or 0
  if (tiltDeg or 0) > (totals.tiltMax or 0) then totals.tiltMax = tiltDeg end
  local b = bucket()
  if sagMeters > b.sagMax then b.sagMax = sagMeters end
  if (tiltDeg or 0) > (b.tiltMax or 0) then b.tiltMax = tiltDeg end
end

function M.evBail(vehId, reason)
  if not enabled then return end
  totals.bails = totals.bails + 1
  bucket().bails = bucket().bails + 1
  pushRecent('BAIL ' .. tostring(reason))
end

-- Runaway-physics detector: a bullet sampled at an impossible speed.
function M.evWild(vehId, shotNo, speed)
  if not enabled then return end
  totals.wild = (totals.wild or 0) + 1
  local b = bucket()
  b.wild = (b.wild or 0) + 1
  pushRecent(string.format('WILD shot=%d speed=%.2e m/s (physics runaway)', shotNo, speed))
end

-- ---------------------------------------------------------------------------
-- Snapshot / dump
-- ---------------------------------------------------------------------------

local function buildSnapshot()
  local minutes = {}
  for m, b in pairs(perMinute) do
    minutes[#minutes + 1] = {
      m = m,
      shots = b.shots,
      impacts = b.impacts,
      selfHits = b.selfHits,
      bails = b.bails,
      hotReuse = b.hotReuse,
      trajAvg = b.trajN > 0 and math.floor((b.trajSum / b.trajN) * 100) / 100 or 0,
      trajMax = math.floor(b.trajMax * 100) / 100,
      vertAvg = b.trajN > 0 and math.floor((b.vertSum / b.trajN) * 100) / 100 or 0,
      latAvg = b.trajN > 0 and math.floor((b.latSum / b.trajN) * 100) / 100 or 0,
      speedAvg = b.trajN > 0 and math.floor(b.spdSum / b.trajN) or 0,
      sagMax = math.floor(b.sagMax * 10000) / 10000,
      tiltMax = math.floor((b.tiltMax or 0) * 100) / 100,
    }
  end
  table.sort(minutes, function(a, b) return a.m < b.m end)

  -- recent events oldest -> newest
  local recentOut = {}
  local n = #recent
  for i = 1, n do
    local idx = ((recentHead + i - 1) % n) + 1
    if recent[idx] then recentOut[#recentOut + 1] = recent[idx] end
  end

  return {
    meta = {
      sessionSec = math.floor(sessionSec),
      enabled = enabled,
      selfHitRadiusM = SELF_HIT_RADIUS,
    },
    totals = {
      shots = totals.shots,
      impacts = totals.impacts,
      selfHits = totals.selfHits,
      bails = totals.bails,
      hotReuseShots = totals.hotReuse,
      wildShots = totals.wild or 0,
      trajErrAvgDeg = totals.trajN > 0 and math.floor((totals.trajSum / totals.trajN) * 100) / 100 or 0,
      trajErrMaxDeg = math.floor(totals.trajMax * 100) / 100,
      trajErrVertAvgDeg = totals.trajN > 0 and math.floor((totals.vertSum / totals.trajN) * 100) / 100 or 0,
      trajErrLatAvgDeg = totals.trajN > 0 and math.floor((totals.latSum / totals.trajN) * 100) / 100 or 0,
      exitSpeedAvgMps = totals.trajN > 0 and math.floor(totals.spdSum / totals.trajN) or 0,
      mountSagNowM = math.floor(totals.sagNow * 10000) / 10000,
      mountSagMaxM = math.floor(totals.sagMax * 10000) / 10000,
      vehTiltNowDeg = math.floor((totals.tiltNow or 0) * 100) / 100,
      vehTiltMaxDeg = math.floor((totals.tiltMax or 0) * 100) / 100,
    },
    perMinute = minutes,
    worstShots = worstShots,
    recent = recentOut,
  }
end

function M.dump()
  local snap = buildSnapshot()
  if jsonWriteFile then
    jsonWriteFile(DUMP_PATH, snap, true)
    log('I', 'playerGuns.telemetry', 'Telemetry dumped to ' .. DUMP_PATH ..
        string.format(' (shots=%d selfHits=%d trajAvg=%.2f)', snap.totals.shots, snap.totals.selfHits, snap.totals.trajErrAvgDeg))
    if guihooks then
      guihooks.message('PlayerGuns telemetry dumped to ' .. DUMP_PATH, 4, 'playerGuns_telemetry')
    end
    return DUMP_PATH
  end
  log('E', 'playerGuns.telemetry', 'jsonWriteFile unavailable — cannot dump')
  return nil
end

function M.reset()
  resetData()
  log('I', 'playerGuns.telemetry', 'Telemetry counters reset')
end

function M.setEnabled(b)
  enabled = b and true or false
  log('I', 'playerGuns.telemetry', 'Telemetry recording ' .. (enabled and 'ENABLED' or 'DISABLED'))
end

function M.isEnabled()
  return enabled
end

-- UI snapshot for the PlayerGunsDebug app (small subset, pushed periodically).
local function publishUi()
  if not guihooks or not guihooks.trigger then return end
  local trajAvg = totals.trajN > 0 and (totals.trajSum / totals.trajN) or 0
  guihooks.trigger('playerGuns_telemetry', {
    enabled = enabled,
    sessionSec = math.floor(sessionSec),
    shots = totals.shots,
    impacts = totals.impacts,
    selfHits = totals.selfHits,
    bails = totals.bails,
    hotReuse = totals.hotReuse,
    trajAvg = math.floor(trajAvg * 100) / 100,
    trajMax = math.floor(totals.trajMax * 100) / 100,
    sagNow = math.floor(totals.sagNow * 10000) / 10000,
    sagMax = math.floor(totals.sagMax * 10000) / 10000,
  })
end

function M.onUpdate(dtReal, dtSim)
  if enabled then
    sessionSec = sessionSec + (dtReal or 0)
  end
  _uiAccum = _uiAccum + (dtReal or 0)
  if _uiAccum >= UI_INTERVAL then
    _uiAccum = 0
    publishUi()
  end
end

function M.onExtensionLoaded()
  log('I', 'playerGuns.telemetry', 'PlayerGuns telemetry recorder loaded (dump: extensions.playerGuns_telemetry.dump())')
end

return M
