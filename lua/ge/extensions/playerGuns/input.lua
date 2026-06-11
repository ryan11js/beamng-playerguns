-- PlayerGuns input bridge (GE).
--
-- Rebinding now writes NATIVE BeamNG bindings through core_input_bindings:
-- we clone the device's current inputmap from core_input_bindings.bindings,
-- edit the pg_* action entries, and call core_input_bindings.saveBindingsToDisk
-- (the exact code path the stock Options > Controls menu uses; it diffs against
-- defaults and writes settings/inputmaps/<devicetype>.diff). No manual GE-side
-- polling, no saveAllDevices (that historically broke the orbit camera).
--
-- Input itself is delivered by BeamNG's action system: the pg_* actions in
-- lua/ge/extensions/core/input/actions/playerGuns.json set electrics on the
-- active vehicle via their onChange handlers.

local M = {}

local SETTINGS_PATH = 'settings/playerGuns/keybinds.json'

-- Recoil/spread OFF by default; persisted and pushed into the active vehicle's
-- electrics (pg_recoil_enabled). Vehicle-side bullets.lua skips the spread cone
-- when disabled.
local recoilEnabled = false

-- Aim convergence: OFF (default) = bullets fly along the camera-forward rayDir
-- from the muzzle. ON = bullets aim at the world point the crosshair ray hit.
local aimConvergeEnabled = false

local PG_ACTIONS = {
  { action = 'pg_fire',        title = 'Fire' },
  { action = 'pg_reload',      title = 'Reload' },
  { action = 'pg_weaponDown',  title = 'Prev Weapon' },
  { action = 'pg_weaponUp',    title = 'Next Weapon' },
  { action = 'pg_weaponWheel', title = 'Weapon Wheel (hold)' },
}

local PG_ACTION_SET = {}
for _, a in ipairs(PG_ACTIONS) do PG_ACTION_SET[a.action] = true end

local active = false

-- Pretty labels for common control names (fallback: uppercase the raw name).
local CONTROL_LABELS = {
  button0 = 'LMB', button1 = 'MMB', button2 = 'RMB', button3 = 'Mouse4', button4 = 'Mouse5',
  btn_a = 'A', btn_b = 'B', btn_x = 'X', btn_y = 'Y',
  btn_l = 'LB', btn_r = 'RB', btn_lt = 'L3', btn_rt = 'R3',
  btn_back = 'Back', btn_start = 'Start',
  triggerl = 'LT', triggerr = 'RT',
  upov = 'D-Up', dpov = 'D-Down', lpov = 'D-Left', rpov = 'D-Right',
  space = 'Space', lshift = 'LShift', rshift = 'RShift',
  lcontrol = 'LCtrl', rcontrol = 'RCtrl', lalt = 'LAlt', ralt = 'RAlt',
  up = 'ArrowUp', down = 'ArrowDown', left = 'ArrowLeft', right = 'ArrowRight',
  comma = ',', period = '.', slash = '/', semicolon = ';', apostrophe = "'",
  lbracket = '[', rbracket = ']', minus = '-', equals = '=', backslash = '\\',
}

local function controlLabel(control)
  return CONTROL_LABELS[control] or string.upper(tostring(control))
end

local function loadSettings()
  recoilEnabled = false
  aimConvergeEnabled = false
  if jsonReadFile then
    local data = jsonReadFile(SETTINGS_PATH)
    if type(data) == 'table' and type(data._meta) == 'table' then
      if data._meta.recoilEnabled ~= nil then
        recoilEnabled = data._meta.recoilEnabled and true or false
      end
      if data._meta.aimConvergeEnabled ~= nil then
        aimConvergeEnabled = data._meta.aimConvergeEnabled and true or false
      end
    end
  end
end

local function saveSettings()
  if not jsonWriteFile then return end
  jsonWriteFile(SETTINGS_PATH, {
    _meta = { recoilEnabled = recoilEnabled, aimConvergeEnabled = aimConvergeEnabled },
  }, true)
end

-- Push current toggles to the active player vehicle's electrics. Called on
-- toggle change and on activation/vehicle switch so a freshly spawned vehicle
-- picks up the persisted preferences.
local function pushTogglesToVehicle()
  if not be or not be.getPlayerVehicle then return end
  local veh = be:getPlayerVehicle(0)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand(string.format(
    'if electrics and electrics.values then ' ..
      'electrics.values.pg_recoil_enabled = %d ' ..
      'electrics.values.pg_aim_converge_enabled = %d ' ..
    'end',
    recoilEnabled and 1 or 0,
    aimConvergeEnabled and 1 or 0
  ))
end

-- ---------------------------------------------------------------------------
-- Native binding access
-- ---------------------------------------------------------------------------

local function deviceEntries()
  if core_input_bindings and core_input_bindings.bindings then
    return core_input_bindings.bindings
  end
  return {}
end

-- All current native bindings for our pg_* actions, grouped per action.
local function collectPgBindings()
  local byAction = {}
  for _, a in ipairs(PG_ACTIONS) do byAction[a.action] = {} end
  for _, dev in ipairs(deviceEntries()) do
    local contents = dev.contents or {}
    for _, b in ipairs(contents.bindings or {}) do
      if PG_ACTION_SET[b.action] then
        table.insert(byAction[b.action], {
          devname = dev.devname,
          devicetype = contents.devicetype,
          control = b.control,
          label = controlLabel(b.control),
        })
      end
    end
  end
  return byAction
end

-- Other (non-pg) actions already bound to a control on a device — for the
-- conflict hint in the UI.
local function findConflicts(devname, control)
  local out = {}
  for _, dev in ipairs(deviceEntries()) do
    if dev.devname == devname then
      for _, b in ipairs((dev.contents or {}).bindings or {}) do
        if b.control == control and not PG_ACTION_SET[b.action] then
          table.insert(out, b.action)
        end
      end
    end
  end
  return out
end

local function findDeviceByType(devicetype)
  for _, dev in ipairs(deviceEntries()) do
    if (dev.contents or {}).devicetype == devicetype then
      return dev
    end
  end
  return nil
end

local function publishBindingsUi()
  if guihooks and guihooks.trigger then
    guihooks.trigger('playerGuns_bindings', M.getBindings())
  end
end

-- Set (or move) a native binding: action -> control on device type
-- ('keyboard' / 'mouse' / 'xinput'). Returns list of conflicting action names
-- (other actions already on that control), or nil on failure.
function M.setBinding(actionName, devicetype, control)
  if not PG_ACTION_SET[actionName] then return nil end
  if not (core_input_bindings and core_input_bindings.saveBindingsToDisk) then
    log('E', 'playerGuns.input', 'core_input_bindings unavailable — cannot save binding')
    return nil
  end
  local dev = findDeviceByType(devicetype)
  if not dev then
    log('W', 'playerGuns.input', 'No connected device of type ' .. tostring(devicetype))
    return nil
  end

  local conflicts = findConflicts(dev.devname, control)

  -- Remove this action from EVERY device of this type (a rebind is a move, not
  -- an add), then insert the new binding and save each touched device.
  for _, d in ipairs(deviceEntries()) do
    if (d.contents or {}).devicetype == devicetype then
      local data = deepcopy(d.contents)
      local changed = false
      for i = #data.bindings, 1, -1 do
        if data.bindings[i].action == actionName then
          table.remove(data.bindings, i)
          changed = true
        end
      end
      if d.devname == dev.devname then
        table.insert(data.bindings, { action = actionName, control = control })
        changed = true
      end
      if changed then
        core_input_bindings.saveBindingsToDisk(data)
      end
    end
  end

  log('I', 'playerGuns.input', string.format('Bound %s -> %s/%s%s',
    actionName, devicetype, control,
    #conflicts > 0 and (' (also used by: ' .. table.concat(conflicts, ', ') .. ')') or ''))
  publishBindingsUi()
  return conflicts
end

-- Remove the action's binding from all devices of the given type (or all
-- devices when devicetype is nil).
function M.clearBinding(actionName, devicetype)
  if not PG_ACTION_SET[actionName] then return end
  if not (core_input_bindings and core_input_bindings.saveBindingsToDisk) then return end
  for _, d in ipairs(deviceEntries()) do
    local contents = d.contents or {}
    if devicetype == nil or contents.devicetype == devicetype then
      local data = deepcopy(contents)
      local changed = false
      for i = #data.bindings, 1, -1 do
        if data.bindings[i].action == actionName then
          table.remove(data.bindings, i)
          changed = true
        end
      end
      if changed then
        core_input_bindings.saveBindingsToDisk(data)
      end
    end
  end
  publishBindingsUi()
end

-- Reset = re-apply the shipped defaults (settings/inputmaps/*_playerGuns.json:
-- LMB fire, Q reload, O/P switch). Note: simply clearing would UNBIND the
-- actions (the diff would record the defaults as removed), so we explicitly
-- set the default controls instead — the resulting diff vs defaults is empty.
function M.resetBindings()
  M.clearBinding('pg_fire', 'xinput')
  M.clearBinding('pg_reload', 'xinput')
  M.clearBinding('pg_weaponDown', 'xinput')
  M.clearBinding('pg_weaponUp', 'xinput')
  M.clearBinding('pg_weaponWheel', 'xinput')
  M.setBinding('pg_fire', 'mouse', 'button0')
  M.setBinding('pg_reload', 'keyboard', 'q')
  M.setBinding('pg_weaponDown', 'keyboard', 'o')
  M.setBinding('pg_weaponUp', 'keyboard', 'p')
  M.setBinding('pg_weaponWheel', 'keyboard', 'x')
  publishBindingsUi()
end

function M.getBindings()
  local byAction = collectPgBindings()
  local out = {
    active = active,
    recoilEnabled = recoilEnabled,
    aimConvergeEnabled = aimConvergeEnabled,
    hasController = findDeviceByType('xinput') ~= nil,
    actions = {},
  }
  for _, a in ipairs(PG_ACTIONS) do
    table.insert(out.actions, {
      action = a.action,
      title = a.title,
      binds = byAction[a.action],
    })
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Activation probe (drives the "Active" indicator + toggle push)
-- ---------------------------------------------------------------------------

local function probeActiveOnVehicle(vehId)
  if not be or not be.getObjectByID then return end
  local veh = be:getObjectByID(vehId)
  if not veh then
    M._setActive(false)
    return
  end
  veh:queueLuaCommand([[
    local has = electrics and electrics.values and electrics.values.pg_active == 1
    obj:queueGameEngineLua('extensions.playerGuns_input._setActive(' .. tostring(has) .. ')')
  ]])
end

function M._setActive(isActive)
  local wasActive = active
  active = isActive and true or false
  if active and not wasActive then
    log('I', 'playerGuns.input', 'PlayerGuns controller active on player vehicle.')
    pushTogglesToVehicle()
  elseif not active and wasActive then
    log('I', 'playerGuns.input', 'PlayerGuns controller inactive.')
  end
  publishBindingsUi()
end

function M.isActive()
  return active
end

-- Weapon wheel selection: forwards the chosen index to the player vehicle.
function M.selectWeapon(idx)
  idx = math.floor(tonumber(idx) or 0)
  if idx < 1 then return end
  if not be or not be.getPlayerVehicle then return end
  local veh = be:getPlayerVehicle(0)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand(string.format(
    'local c = controller.getControllerSafe("playerGuns") if c and c.selectWeapon then c.selectWeapon(%d) end', idx))
end

function M.setActive(isActive)
  M._setActive(isActive)
end

-- ---------------------------------------------------------------------------
-- Toggles
-- ---------------------------------------------------------------------------

function M.setRecoilEnabled(enabled)
  recoilEnabled = enabled and true or false
  saveSettings()
  pushTogglesToVehicle()
  publishBindingsUi()
  log('I', 'playerGuns.input', 'Recoil ' .. (recoilEnabled and 'ENABLED' or 'DISABLED'))
end

function M.getRecoilEnabled()
  return recoilEnabled
end

function M.setAimConvergeEnabled(enabled)
  aimConvergeEnabled = enabled and true or false
  saveSettings()
  pushTogglesToVehicle()
  publishBindingsUi()
  log('I', 'playerGuns.input', 'Aim convergence ' .. (aimConvergeEnabled and 'ENABLED' or 'DISABLED'))
end

function M.getAimConvergeEnabled()
  return aimConvergeEnabled
end

function M.onExtensionLoaded()
  loadSettings()
  publishBindingsUi()
  log('I', 'playerGuns.input', 'PlayerGuns input bridge loaded (native bindings).')
  if be and be.getPlayerVehicle then
    local veh = be:getPlayerVehicle(0)
    if veh and veh.getID then
      probeActiveOnVehicle(veh:getID())
    end
  end
end

function M.onVehicleSwitched(oldID, newID, player)
  active = false
  if newID then
    probeActiveOnVehicle(newID)
  else
    publishBindingsUi()
  end
end

return M
