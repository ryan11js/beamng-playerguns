-- Crosshair screen position (GE mouse poll) + camera-ray aim on the vehicle.

local M = {}

local crosshairX = 0.5
local crosshairY = 0.5
local _uiTickAccum = 0
local UI_INTERVAL = 1 / 60
local _lastPublishX, _lastPublishY = -1, -1

local function getViewport()
  local w, h = 1920, 1080
  if Window and Window.getVideoMode then
    local ok, vm = pcall(Window.getVideoMode)
    if ok and vm and vm.w and vm.h and vm.h > 0 then
      w, h = vm.w, vm.h
    end
  end
  return w, h
end

local function getAspectRatio()
  local w, h = getViewport()
  if h > 0 then return w / h end
  return 16 / 9
end

local function getFovRad()
  local fovDeg = 70
  if core_camera and core_camera.getFov then
    local ok, v = pcall(core_camera.getFov)
    if ok and type(v) == 'number' and v > 0 then fovDeg = v end
  end
  return math.rad(fovDeg)
end

function M.setCrosshair(x, y)
  if type(x) == 'number' then crosshairX = math.max(0, math.min(1, x)) end
  if type(y) == 'number' then crosshairY = math.max(0, math.min(1, y)) end
end

function M.getCrosshair()
  return crosshairX, crosshairY
end

function M.pollMouseScreenNorm()
  local w, h = getViewport()
  local nx, ny = crosshairX, crosshairY
  local source = 'unchanged'

  if core_input and core_input.getMousePos then
    local ok, pos = pcall(core_input.getMousePos)
    if ok and pos and pos.x and pos.y then
      nx = pos.x / w
      ny = pos.y / h
      source = 'core_input'
    end
  end

  if source == 'unchanged' and WinInput and WinInput.mouse then
    local mx = WinInput.mouse.x or WinInput.mouse.X
    local my = WinInput.mouse.y or WinInput.mouse.Y
    if mx and my then
      nx = mx / w
      ny = my / h
      source = 'WinInput'
    end
  end

  if source == 'unchanged' and Screen and Screen.getMousePos then
    local ok, pos = pcall(Screen.getMousePos)
    if ok and pos and pos.x and pos.y then
      nx = pos.x / w
      ny = pos.y / h
      source = 'Screen'
    end
  end

  nx = math.max(0, math.min(1, nx))
  ny = math.max(0, math.min(1, ny))
  M.setCrosshair(nx, ny)

  if guihooks and guihooks.trigger then
    if math.abs(nx - _lastPublishX) > 0.0005 or math.abs(ny - _lastPublishY) > 0.0005 then
      _lastPublishX = nx
      _lastPublishY = ny
      guihooks.trigger('playerGuns_crosshair', { x = nx, y = ny, visible = true })
    end
  end

  return nx, ny, source
end

function M.getCameraRayDir(normX, normY)
  local forward = core_camera.getForward():normalized()
  local upWorld = vec3(0, 0, 1)
  local right = forward:cross(upWorld)
  if right:length() < 0.001 then right = vec3(1, 0, 0) end
  right = right:normalized()
  local up = right:cross(forward):normalized()

  local nx = (normX - 0.5) * 2
  local ny = (0.5 - normY) * 2
  local tanHalf = math.tan(getFovRad() * 0.5)
  local aspect = getAspectRatio()

  return (forward + right * (nx * tanHalf * aspect) + up * (ny * tanHalf)):normalized()
end

-- Convergence min: ignore hits closer than this so a stray camera-clipping-terrain
-- hit doesn't yank the aim downward.
local CONVERGE_MIN_DIST = 2.0
-- "Shallow-close" filter: when aiming roughly horizontal (rayDir.z > -0.5,
-- i.e. less than 30 deg below horizon) any hit within this distance is almost
-- always foreground terrain just past the car, not a target the player wants.
-- Treat it as no-hit so the bullet flies into the distance instead of into
-- the dirt 10m ahead. Sharp-down aim (steep crosshair on the ground) still
-- honors the hit so deliberate ground shots work.
local SHALLOW_CLOSE_MAX_DIST = 25.0
local SHALLOW_RAY_Z_THRESHOLD = -0.5
-- Fallback bumped 300 -> 1500 so no-hit shots fly to a believable horizon
-- target. With 300m the parallax math for roof mounts (muzzle 1m+ above cam)
-- was kicking bullets up at noticeable angles.
local CONVERGE_FAR_FALLBACK = 1500.0

-- Diagnostic throttling (~30 aim pushes/sec -> one log line every ~20s).
local _diagAimEveryN = 600
local _diagAimCallCount = 0

function M.pushAimRayToVehicle(vehId)
  local veh = be:getObjectByID(vehId)
  if not veh or not veh.queueLuaCommand then return end

  local ok, rayDir = pcall(M.getCameraRayDir, crosshairX, crosshairY)
  if not ok or not rayDir or rayDir:length() < 0.01 then return end

  -- Cast the crosshair ray to find world-space hit point. The vehicle decides
  -- whether to USE this for parallax convergence based on its own toggle
  -- (pg_aim_converge_enabled electric). We always send both target + rayDir
  -- so the vehicle can pick.
  local camPos = core_camera.getPosition()
  local hitDist = nil
  local hitOk = false
  if castRayStatic then
    local okR, d = pcall(castRayStatic, camPos, rayDir, 2000)
    if okR and type(d) == 'number' then
      hitOk = true
      hitDist = d
    end
  end

  local dist
  local convergeSource
  if hitOk and hitDist and hitDist < 2000 then
    if hitDist < CONVERGE_MIN_DIST then
      dist = CONVERGE_FAR_FALLBACK
      convergeSource = 'near-skip'
    elseif hitDist < SHALLOW_CLOSE_MAX_DIST and rayDir.z > SHALLOW_RAY_Z_THRESHOLD then
      -- Close hit but the camera is looking roughly forward — probably
      -- foreground terrain, not an intended target. Bullet will fly past.
      dist = CONVERGE_FAR_FALLBACK
      convergeSource = 'shallow-close-skip'
    else
      dist = hitDist
      convergeSource = 'hit'
    end
  else
    dist = CONVERGE_FAR_FALLBACK
    convergeSource = hitOk and 'no-hit' or 'no-api'
  end
  local target = camPos + rayDir * dist

  _diagAimCallCount = _diagAimCallCount + 1
  if (_diagAimCallCount % _diagAimEveryN) == 1 then
    log('I', 'playerGuns.aim', string.format(
      'aim #%d veh=%d cam=(%.2f,%.2f,%.2f) rayDir=(%.3f,%.3f,%.3f) hitDist=%s -> dist=%.2f (%s) target=(%.2f,%.2f,%.2f)',
      _diagAimCallCount, vehId, camPos.x, camPos.y, camPos.z,
      rayDir.x, rayDir.y, rayDir.z,
      hitDist and string.format('%.2f', hitDist) or 'nil',
      dist, convergeSource,
      target.x, target.y, target.z))
  end

  -- Send target (for convergence mode) AND rayDir (for no-convergence mode).
  -- Vehicle picks based on pg_aim_converge_enabled.
  veh:queueLuaCommand(string.format([[
    local ctrl = controller.getControllerSafe('playerGuns')
    if ctrl and ctrl.camForwardCallback then
      electrics.values.pg_crosshair_x = %f
      electrics.values.pg_crosshair_y = %f
      electrics.values.pg_ray_dir_x = %f
      electrics.values.pg_ray_dir_y = %f
      electrics.values.pg_ray_dir_z = %f
      ctrl.camForwardCallback(%f, %f, %f)
    end
  ]], crosshairX, crosshairY,
      rayDir.x, rayDir.y, rayDir.z,
      target.x, target.y, target.z))
end

function M.onUpdate(dt)
  -- Crosshair scrapped: GE-side mouse position is unreadable here, so the reticle
  -- could never track in third person. Aim uses screen-center (crosshair 0.5,0.5)
  -- via pushAimRayToVehicle(), which is driven from the vehicle controller.
end

return M
